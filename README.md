# Asana Perl Library
## Overview
This is a Perl library for the Asana API.  It is generated at runtime from the
OpenAPI specification published by Asana.  It supports:
- All endpoints
- Pagination
- Rate limiting
- Automatic retry
- Error handling


## Installation
```bash
git clone git@github.com:kablamo/perl-asana-api.git
carton
```

## Explore the Asana API with asana-cli
```bash
bin/asana-cli --help
bin/asana-cli list  # list all endpoints
bin/asana-cli doc get_tasks  # show documentation for the get_tasks endpoint
bin/asana-cli call get_tasks  '{"task_gid":"11223344"}' # call the get_tasks endpoint with a task_gid parameter
```

## How to use the library in your code
For complete documentation, see the [documentation](https://github.com/kablamo/perl-asana-api/blob/main/lib/Asana/Documentation.pm).

```perl
use Asana;
use DDP;

# Instantiate the client
my $asana = Asana->new();

# Get a task
my $response = $asana->get_task(task_gid => '123');
print "Task Title:       " . $response->{name}  . "\n";
print "Task Description: " . $response->{notes} . "\n";

# Create a task
my $response = $asana->create_task(
    name     => 'Example Task',
    assignee => 'user@example.com',
    notes    => 'This is an example task.',
);
print "Create Task GID: " . $response->{gid} . "\n";

# Pagination Approach 1: Allows you to bail out early
my $response = $asana->get_tasks(project => '123');
while (my $task = $response->next_item) {
    print "Task: $task->{name}\n";
}

# Pagination Approach 2: CAUTION - Can slurp unlimited items from the api
my $response = $asana->get_tasks(project => '123');
my @tasks = $response->all_items(max_items => 10_000);
for my $task (@tasks) {
    print "Task: $task->{name}\n";
}
```
