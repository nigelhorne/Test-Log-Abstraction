package Capture;

# Shared by the tests: run code and return what it printed through
# Test::Builder's diag(), without that output reaching the TAP stream.

use strict;
use warnings;
use autodie qw(:all);

use Exporter qw(import);
use Test::Builder;

our @EXPORT_OK = qw(capture_diag);

# capture_diag - capture diagnostics printed while running a block
#
# Purpose:      Let a test assert on what the logger prints.
# Entry:        $code - code reference to run.
# Exit:         Returns the captured text; rethrows anything $code died with,
#               after restoring the handles.
# Side effects: Temporarily replaces Test::Builder's failure and TODO
#               output handles, which is where diag() writes.
sub capture_diag(&) {
	my $code = shift;

	my $tb = Test::Builder->new();
	my $captured = '';
	open(my $sink, '>', \$captured);

	# failure_output($fh) returns the handle it just set, so fetch the
	# originals first, without an argument
	my @original = ($tb->failure_output(), $tb->todo_output());
	$tb->failure_output($sink);
	$tb->todo_output($sink);

	my $ok = eval { $code->(); 1 };
	my $error = $@;

	$tb->failure_output($original[0]);
	$tb->todo_output($original[1]);
	close($sink);
	die $error if(!$ok);

	return $captured;
}

1;
