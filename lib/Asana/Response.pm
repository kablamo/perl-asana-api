package Asana::Response;
use Moo;
use JSON::MaybeXS qw//;

# response related attributes
has response => (is => 'ro', required => 1);
has data     => (is => 'rw', lazy => 1, builder => 1);
has raw      => (is => 'rw', lazy => 1, builder => 1);
has json     => (is => 'rw', lazy => 1, builder => 1);

# attributes to request the next page of results
has client   => (is => 'rw', required => 1);
has sub_name => (is => 'ro', required => 1);
has params   => (is => 'ro', required => 1);

# misc
has jsonxs   => (is => 'rw', lazy => 1, builder => 1);
has index    => (is => 'rw', default => sub { 0 });

sub _build_jsonxs {
    return JSON::MaybeXS->new->utf8->canonical
        ->pretty->space_before(0)->indent_length(2);
};

sub _build_data {
    return shift->raw->{data};
}

sub _build_json {
    return shift->response->decoded_content;
}

sub _build_raw {
    my $self = shift;
    my $json = $self->response->decoded_content;
    return $self->jsonxs->decode($json);
}

# Gets the next page of results if available and updates the object.
sub get_next_page {
    my $self = shift;

    return unless ref $self->data eq 'HASH'
        && $self->data->{next_page}
        && $self->data->{next_page}->{offset};

    no strict 'refs';

    my $sub_name = $self->sub_name;
    my $items    = $self->data || [];
    my $offset   = $self->raw->{next_page}->{offset};
    my $response = $self->client->$sub_name(%{$self->params}, offset => $offset);

    $self->response($response);
    $self->clear_data;
    $self->clear_raw;
}

# Resets the index to 0, allowing iteration to start over.
# This does not clear the already fetched data
sub reset { shift->index(0) }

# Returns the current item in the list, or undef if there are no items.
sub next_item {
    my $self = shift;

    return unless ref $self->data eq 'HASH'
        && $self->data->{next_page}
        && $self->data->{next_page}->{offset};

    $self->index($self->index + 1);

    # If no more items, fetch the next page of items
    $self->get_next_page if $self->index < @{ $self->data };

    # Return the next item in the list
    return $self->data->[$self->index];
}

# Returns an array of all items, fetching more pages if necessary.
sub all_items {
    my ($self, %args) = @_;
    my $max_items = $args{max_items} // 0;

    # Return early if we already have enough items
    return $self->data if $max_items && @{ $self->data } >= $max_items;

    while ($self->get_next_page) {
        # If we have reached the $item limit, stop fetching more items
        last if $max_items && @{ $self->data } >= $max_items;
    }

    return $self->data;
}

1;
