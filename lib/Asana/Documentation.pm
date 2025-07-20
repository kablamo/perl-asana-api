package Asana::Documentation;
1;

# SYNOPSIS
#
#    use Asana;
#    use DDP;
#
#    # Instantiate the client
#    my $asana = Asana->new();
#
#    # Get a task
#    my $response = $asana->get_task(task_gid => '123');
#    print "Task Title:       " . $response->{name}  . "\n";
#    print "Task Description: " . $response->{notes} . "\n";
#
#    # Create a task
#    my $response = $asana->create_task(
#        name     => 'Example Task',
#        assignee => 'user@example.com',
#        notes    => 'This is an example task.',
#    );
#    print "Create Task GID: " . $response->{gid} . "\n";
#
#    # Pagination Approach 1: Allows you to bail out early
#    my $response = $asana->get_tasks(project => '123');
#    while (my $task = $response->next_item) {
#        print "Task: $task->{name}\n";
#    }
#
#    # Pagination Approach 2: CAUTION - Can slurp unlimited items from the api
#    my $response = $asana->get_tasks(project => '123');
#    my @tasks = $response->all_items(max_items => 10_000);
#    for my $task (@tasks) {
#        print "Task: $task->{name}\n";
#    }
#
# 
# DESCRIPTION
#
# This module provides a Perl interface to the Asana API. 
#
# All methods and documentation are generated dynamically on instantiation
# based on the OpenAPI specification located on the local disk at
# $SPECIFICATION.  
#
# The specification is a YAML file that describes the Asana API.  It is
# maintained by Asana who uses it to generate client libraries across mulitple
# languages.  For most API changes we can just update the file at
# $SPECIFICATION and not have to change any code.
# 
# 
# AUTHENTICATION
#
# Set the ASANA_API_KEY environment variable to your personal access token.
# 
#
# AUTO REQUEST RETRY
#
# The client will automatically retry requests $DDG_ASANA_MAX_RETRIES times with a $DDG_ASANA_RETRY_WAIT second wait in
# between.  If a request fails due to rate limiting it will obey the
# Retry-After header.
#
# 
# ON THE COMMAND LINE
#
# To call a method directly, you can run:
#     export ASANA_API_KEY=<your_api_key>
#     asana-cli call <method_name> <args_as_json>
#
# To search for methods available in this module, run the following command:
#     asana-cli list [<keyword>]
#
# To view the documentation for a specific method, run the following command:
#     asana-cli doc <method_name>
#
# 
# METHODS
#
# All methods below accept a hash (dictionary).  The hash can include
# path, query, and body parameters.  The function will apply them appropriately
# based on the OpenAPI specification.
#
#
