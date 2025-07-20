package Asana;
use Moo;

#            !!!!!!!!!!!!!!!README!!!!!!!!!!!!!!!
#
# For extensive docs for this class and each method see Asana::Documentation.
#
#            !!!!!!!!!!!!!!!README!!!!!!!!!!!!!!!

use DDP;
use JSON::Validator;
use JSON::MaybeXS qw//;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Date qw(str2time);
use URI::URL;

use Asana::Response;

our $SPECIFICATION = "file:///home/eric/code/perl-asana-api/asana_oas.yaml";
our $DDG_ASANA_MAX_RETRIES = $ENV{DDG_ASANA_MAX_RETRIES} || 3;
our $DDG_ASANA_RETRY_WAIT  = $ENV{DDG_ASANA_RETRY_WAIT} || 3;
our $WORKSPACE_GID         = $ENV{ASANA_WORKSPACE_GID} || '76443487521226';

has personal_access_token => (is => 'rw', builder => 1);
has validator             => (is => 'rw', lazy => 1, builder => 1, handles => [qw/schema/]);
has base_url              => (is => 'rw', lazy => 1, builder => 1);
has ua                    => (is => 'rw', lazy => 1, builder => 1);
has jsonxs                => (is => 'rw', lazy => 1, builder => 1);

sub _build_personal_access_token {
    $ENV{ASANA_API_KEY} || die "ASANA_API_KEY environment variable is not set.";
}

sub _build_validator {
    my $self = shift;
    my $validator = JSON::Validator->new;
    $validator->coerce('booleans,numbers,strings');
    $validator->schema($SPECIFICATION);
    return $validator;
}

sub _build_base_url {
    return shift->validator->schema->base_url;
}

sub _build_ua {
    return LWP::UserAgent->new(
        timeout => 10,
        agent   => 'Asana-Perl-Client/1.0',
    );
}

sub _build_jsonxs { 
    return JSON::MaybeXS->new->utf8->canonical
        ->pretty->space_before(0)->indent_length(2);
}

# Build subroutines dynamically from $SPECIFICATION on instantiation
sub BUILD {
    my $self = shift;

    # Loop over every api endpoint in $SPECIFICATION
    for my $route ($self->schema->routes->each) {
        my $op_id  = $route->{operation_id} || next;
        my $method = $route->{method};
        my $path   = $route->{path};

        # The operation id defined in $SPECIFICATION is camel case.  But snake
        # case is standard for subroutine names in Perl.
        my $sub_name = $self->camel_to_snake($op_id);

        # Create a subroutine for this api endpoint
        no strict 'refs';
        *{"Asana::$sub_name"} = $self->_build_subroutine($sub_name, $method, $path);
    }
}

sub _build_subroutine {
    my ($self, $sub_name, $method, $path) = @_;

    # All $SPECIFICATION magic should be done here and not in call_api().
    return sub {
        my ($self, %params) = @_;

        # Returns a hashref containing path, query, body, header values using
        # %params and the api endpoint definition in $SPECIFICATION.
        my $p = $self->build_api_params($method, $path, %params);

        # Generate $body from body params
        my $body;
        $body = $self->jsonxs->encode($p->{body})
            if $p->{headers}
            && $p->{headers}->{"Content-Type"}
            && $p->{headers}->{"Content-Type"} =~ m'application/json';

        # Make a request to the Asana API
        # $response is an HTTP::Response object
        my $response = $self->call_api(
            method       => $method,
            path         => $path,
            path_params  => $p->{path},
            query_params => $p->{query},
            body         => $body,
            headers      => $p->{headers},
        );

        # Build and return the Asana::Response object
        return Asana::Response->new(
            response => $response,
            params   => \%params,
            sub_name => $sub_name,
            client   => $self,
        );
    };
}

sub build_api_params {
    my ($self, $method, $path, %params) = @_;

    # Get the operation specification (api endpoint definition) for this route
    my $op_spec = $self->schema->get(['paths'])->{$path};

    # Get the complete list of params for the api endpoint from the $SPECIFICATION
    my $param_names = $self->get_endpoint_param_names($method, $op_spec);
    my $path_param_names  = $param_names->{path};
    my $query_param_names = $param_names->{query};

    # Path Parameters: Replace {param} in $path with the value from $params
    my $path_params = {};
    for my $name (@$path_param_names) {
        die "'$name' parameter is required." 
            unless $params{$name} || $name eq 'workspace_gid';
        $path_params->{$name} = delete $params{$name};
        $path_params->{$name} = $WORKSPACE_GID 
            if $name eq 'workspace_gid' && !$path_params->{$name};
    }

    # Query Parameters: Append query params to the path
    my $query_params = {};
    for my $name (@$query_param_names) {
        next unless $params{$name};
        $query_params->{$name} = delete $params{$name};
    }

    return {
        path    => $path_params,
        query   => $query_params,
        body    => %params ? \%params : undef, # Remaining params are body params
        headers => $self->build_headers($method, $op_spec, %params),
    };
}

sub build_headers {
    my ($self, $method, $op_spec, %params) = @_;
    my $headers;

    if ($op_spec->{$method}->{requestBody}) {
        my $request_body = $op_spec->{$method}->{requestBody};
        my $content_type = (keys %{$request_body->{content}})[0];

        $headers->{"Content-Type"} = delete $params{__content_type} || $content_type;
    }

    return $headers;
}

# Get path and query parameters from the $SPECIFICATION
sub get_endpoint_param_names {
    my ($self, $method, $op_spec) = @_;
    my $path_params  = [];
    my $query_params = [];

    # Get path and query parameters from the operation specification
    my $op_params = $op_spec->{parameters};
    $self->parse_spec($_, $path_params, $query_params) for @$op_params;

    # Get path and query parameters from the operation > method specification
    my $op_method_params = $op_spec->{$method}->{parameters};
    $self->parse_spec($_, $path_params, $query_params) for @$op_method_params;

    return {
        path  => $path_params, 
        query => $query_params,
    };
}

sub parse_spec {
    my ($self, $param, $path_params, $query_params) = @_;
    my ($param_def, $param_type, $param_name, $param_id);

    if ($param->{'$ref'}) {
        my @path    = split(m|/|, $param->{'$ref'});
        $param_id   = pop @path;
        $param_def  = $self->schema->get(['components', 'parameters', $param_id]);
        $param_name = $param_def->{name} || $param_id;
        $param_type = $param_def->{in} || 'query';
    }
    else {
        $param_name = $param->{name};
        $param_type = $param->{in} || 'query';
    }

    push @$path_params, $param_name  if $param_type eq 'path';
    push @$query_params, $param_name if $param_type eq 'query';
}

# Devs may call this method to make API calls directly if something is off in
# $SPECIFICATION.  Do not put any $specification-based magic here.  That should
# all happen in _build_subroutine().
sub call_api {
    my ($self, %args) = @_;

    # Validate parameters
    my $method       = $args{method}  || die "'method' param is required.";
    my $path         = $args{path}    || die "'path' param is required.";
    my $path_params  = $args{path_params};
    my $query_params = $args{query_params};
    my $body         = $args{body};
    my $headers      = $args{headers} || {};

    # Build the request
    my $url = $self->build_url($path, $path_params, $query_params);
    my $req = HTTP::Request->new(uc $method => $url);
    $req->authorization('Bearer ' . $self->personal_access_token);
    $req->content($body) if $body;
    $req->header('Accept' => 'application/json; charset=utf-8');
    $req->header($_ => $headers->{$_}) for keys %$headers;

    # Retry logic
    my $attempts = 0;
    my $res;
    while ($attempts <= $DDG_ASANA_MAX_RETRIES) {

        # Make the request
        $res = $self->ua->request($req);

        # Return if successful
        return $res if $res->is_success;
        
        # Retry if not successful
        my $msg = "($attempts of $DDG_ASANA_MAX_RETRIES retries).\n";

        if ($res->code == 429) {
            my $seconds = $self->_parse_retry_after_header($res);
            print "Asana rate limit exceeded. Retrying in $seconds $msg";
            sleep($seconds);
        }
        elsif ($res->code == 503) {
            my $seconds = $self->_parse_retry_after_header($res);
            print "Asana service unavailable. Retrying in $seconds $msg";
            sleep($seconds);
        }
        elsif ($res->code == 500 || $res->code == 502 || $res->code == 504) {
            printf("Asana server error: %s. Retrying in %s seconds $msg",
                $res->status_line,
                $DDG_ASANA_RETRY_WAIT,
            );
            sleep($DDG_ASANA_RETRY_WAIT);
        }
        else {
            #die "Asana request failed: " . $res->status_line;
            die sprintf("Asana request failed:\n%s\n%s",
                $req->as_string,
                $res->as_string,
            );
        }
        $attempts++;
    }
    die "Asana request failed after $attempts attempts.";
}

# Build the request path from the $path and $params
# For a url like: https://example.com/api/v1/{workspace_gid}/tasks?limit=10
# - path is "/api/v1/tasks/{workspace_gid}"
# - query is ?limit=10
sub build_url {
    my ($self, $path, $path_params, $query_params) = @_;

    # Path Parameters: Replace {param} in $path with the value from $params
    for my $name (keys %$path_params) {
        die "Path parameter '$name' not found in path '$path'" 
            if $path !~ /\{$name\}/;

        $path =~ s/\{$name\}/$path_params->{$name}/g;
    }

    # Query Parameters: Append query params to the path
    for my $name (keys %$query_params) {
        $path .= ($path =~ /\?/)
            ? "&$name=$query_params->{$name}"
            : "?$name=$query_params->{$name}";
    }

    return URI::URL->new($self->base_url . $path)->canonical;
}

sub _parse_retry_after_header {
    my ($self, $res) = @_;
    my $header = $res->header('Retry-After');

    if ($header && $header =~ /^\d+$/) {
        # Retry-After is a delay in seconds
        return int($header);
    } elsif ($header) {
        # Retry-After is an HTTP date
        my $retry_time = HTTP::Date::str2time($header);
        my $calculated_delay = $retry_time ? $retry_time - time : 1;
        return $calculated_delay < 0 ? 1 : $calculated_delay; # Ensure non-negative delay
    }

    return 1; # Default delay
}

sub camel_to_snake {
    my ($self, $camel_case) = @_;

    # Replace uppercase letters with an underscore followed by the lowercase version of the letter
    $camel_case =~ s/(?<=[a-z])([A-Z])/_\L$1/g;  # handle uc letters that follow lc letters
    $camel_case =~ s/([A-Z]{2,})/_\L$1/g;        # handle consecutive uc letters

    # Remove leading underscore if it exists
    $camel_case =~ s/^_//;
 
    # Convert to lowercase
    $camel_case = lc($camel_case);

    return $camel_case;
}


1;
