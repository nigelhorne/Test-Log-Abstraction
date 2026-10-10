#!/usr/bin/env perl

# Logic tests: each decision in the module is treated as a small proof.
# For every condition, one test per outcome - no more - and for compound
# conditions, one test showing each part can change the result on its own
# (so no part is dead code).  Each subtest states its premises.
#
# Values inside an already proven partition are deliberately not repeated:
# t/domain.t covers the partitions; this file proves the logic that
# separates them.

use strict;
use warnings;

use lib 't/lib';
use Test::Most;
use Test::Warnings qw(warning);
use Readonly;
use Capture qw(printed);

use Test::Log::Abstraction;

# White-box: the private decisions are called directly
$Sub::Private::BYPASS = 1;
$Sub::Protected::BYPASS = 1;

Readonly::Scalar my $CLASS => 'Test::Log::Abstraction';
Readonly::Scalar my $FILE => __FILE__;
Readonly::Scalar my $MOST_SEVERE => 0;
Readonly::Scalar my $LEAST_SEVERE => 7;
Readonly::Scalar my $MIDDLE => 3;	# error: a threshold with levels either side
Readonly::Hash my %NAME_FOR => (0 => 'emergency', 1 => 'alert', 2 => 'critical', 3 => 'error', 4 => 'warning', 5 => 'notice', 6 => 'info', 7 => 'debug');
Readonly::Array my @PREDICATES => qw(trace debug info notice warn error critical alert emergency);
Readonly::Hash my %SEVERITY => (
	emergency => 0, alert => 1, critical => 2, error => 3,
	warn => 4, notice => 5, info => 6, debug => 7, trace => 7,
);

{
	package Local::Sub;
	our @ISA = ('Test::Log::Abstraction');
}

sub quiet {
	return $CLASS->new(diag => 'none', verbose => 0, @_);
}

sub at_caller {
	my $text = shift;

	return qr/\A\Q$CLASS: $text\E at \Q$FILE\E line \d+\.?\n?\z/;
}

# ===========================================================================
# new(): which calling form?
#   Premise 1: an object means "clone".
#   Premise 2: otherwise, UNIVERSAL::isa() decides "class name" or "option".
#   Conclusion: four outcomes, one test each.
# ===========================================================================

subtest 'new: the calling form' => sub {
	my $original = quiet(lang => 'fr');
	my $clone = $original->new();
	is($clone->lang(), 'fr', 'object: a clone');
	isnt($clone, $original, '... a new object');

	isa_ok(Test::Log::Abstraction::new('Local::Sub', diag => 'none'), 'Local::Sub', 'a name that isa this class: used as the class');
	is(Test::Log::Abstraction::new(lang => 'de', diag => 'none')->lang(), 'de', 'a name that is not a class: the first option');
	is(ref(Test::Log::Abstraction::new()), $CLASS, 'undef: this class, nothing added to the options');
};

# ===========================================================================
# _args(): which argument shapes reach Params::Get?
#   Premise: Params::Get accepts one hash reference, or an even list with
#            defined keys; it croaks or warns on anything else.
#   Conclusion: two accepted shapes, and each way of failing them.
# ===========================================================================

subtest '_args: the two accepted shapes, and each way to miss them' => sub {
	is_deeply(Test::Log::Abstraction::_args([{ a => 1 }]), { a => 1 }, 'one hash reference: accepted');
	is_deeply(Test::Log::Abstraction::_args([a => 1]), { a => 1 }, 'even list, keys defined: accepted');
	is_deeply(Test::Log::Abstraction::_args([]), {}, 'empty: nothing to pass on');
	is_deeply(Test::Log::Abstraction::_args(['x']), {}, 'one value, not a hash: odd, refused');
	is_deeply(Test::Log::Abstraction::_args([undef, 1]), {}, 'even, but a key undefined: refused');
	is_deeply(Test::Log::Abstraction::_args([1, undef]), { 1 => undef }, 'even, a value undefined: accepted (only keys are checked)');
};

# ===========================================================================
# _diag_rule(): which kind of rule?
#   Premise 1: undef means $config{diag}.
#   Premise 2: 'undef' is not a level name.
#   Conclusion: an undefined default, or an undefined list element, is
#   rejected by the same test as any other bad name - and named 'undef'.
# ===========================================================================

subtest '_diag_rule: every outcome' => sub {
	my $self = quiet();
	is_deeply($self->_diag_rule(['Info']), { levels => { info => 1 } }, 'list of names: a set');
	is_deeply($self->_diag_rule('NONE'), {}, "'none': empty rule");
	is_deeply($self->_diag_rule('All'), { all => 1 }, "'all': everything");
	is_deeply($self->_diag_rule('Error'), { threshold => $MIDDLE }, 'a level name: a threshold');
	is_deeply($self->_diag_rule(undef), { threshold => 4 }, 'undef: the default from %config');

	throws_ok { $self->_diag_rule([undef]) } at_caller(q{invalid diag level 'undef'}), 'undef in a list: rejected as the name undef';
	throws_ok { $self->_diag_rule(['UNDEF']) } at_caller(q{invalid diag level 'UNDEF'}), "the string 'UNDEF' fails the same test";
	throws_ok { $self->_diag_rule({}) } at_caller('diag must be a level name, "all", "none" or an array reference of level names'), 'not a list or a string';
	{
		local $Test::Log::Abstraction::config{'diag'} = undef;
		throws_ok { $self->_diag_rule(undef) } at_caller(q{invalid diag level 'undef'}), 'undef with an undefined default';
	}
	throws_ok { $self->_diag_rule('bogus') } at_caller(q{invalid diag level 'bogus'}), 'any other string';
};

# ===========================================================================
# _diags(): print this message?
#   It prints if ANY of four reasons holds:
#     V: verbose      A: rule 'all'      L: level listed
#     T: threshold rule, level known, severity <= threshold
#   Proof that each reason matters: each one alone gives 1, none gives 0.
#   T itself has three parts; each is shown to decide the result.
# ===========================================================================

subtest '_diags: each reason is enough on its own' => sub {
	my $self = quiet();
	my @rows = (
		[1, {}, 'error', 1, 'V alone'],
		[0, { all => 1 }, 'error', 1, 'A alone'],
		[0, { levels => { error => 1 } }, 'error', 1, 'L alone'],
		[0, { threshold => $MIDDLE }, 'error', 1, 'T alone'],
		[0, {}, 'error', 0, 'none of them'],
	);
	foreach my $row (@rows) {
		my ($verbose, $rule, $level, $want, $name) = @{$row};
		@{$self}{qw(verbose diag_rule)} = ($verbose, $rule);
		is($self->_diags($level), $want, $name);
	}
};

subtest '_diags: each part of the threshold reason decides it' => sub {
	my $self = quiet();
	$self->{'verbose'} = 0;
	$self->{'diag_rule'} = { threshold => $MIDDLE };
	is($self->_diags($NAME_FOR{$MIDDLE}), 1, 'severity == threshold: prints (the boundary is inclusive)');
	is($self->_diags($NAME_FOR{$MIDDLE + 1}), 0, 'severity == threshold + 1: does not print');
	is($self->_diags('nolevel'), 0, 'unknown level: does not print, whatever the threshold');
	$self->{'diag_rule'} = { levels => { error => 1 } };
	is($self->_diags($NAME_FOR{$MOST_SEVERE}), 0, 'no threshold: severity alone does not print');
};

# ===========================================================================
# count(): which messages?
#   Premise: undef means "all"; anything else must be a string.
#   Conclusion: three outcomes.
# ===========================================================================

subtest 'count: every outcome' => sub {
	my $logger = quiet();
	$logger->warn('a');
	$logger->info('b');
	is($logger->count(), 2, 'no level: all');
	is($logger->count('WARN'), 1, 'a level: those, any case');
	throws_ok { $logger->count([]) } at_caller(q{invalid argument: Parameter 'level' must be a string}), 'not a string: refused before anything is counted';
};

# ===========================================================================
# level(): get, set or warn - exactly one
# ===========================================================================

subtest 'level: exactly one of three paths' => sub {
	my $logger = quiet();
	is($logger->level(), $LEAST_SEVERE, 'no name: get');
	is($logger->level('ALERT'), $logger, 'a level name: set, and return the logger');
	is($logger->level(), 1, '... the level was set');
	my $result = 'unset';
	like(warning { $result = $logger->level('bogus') }, at_caller(q{invalid syslog level 'bogus'}), 'anything else: warn');
	ok(!defined($result), '... return undef');
	is($logger->level(), 1, '... and change nothing');
};

# ===========================================================================
# AUTOLOAD: the method name is always defined
#   Premise 1: $AUTOLOAD is always "Package::name".
#   Premise 2: the capture accepts any text after the last '::', even ''.
#   Conclusion: even an empty name is stored, as '' (not undef).
# ===========================================================================

subtest 'AUTOLOAD: the name is never undefined' => sub {
	my $logger = quiet();
	my $empty = '';
	my $out = printed { $logger->$empty('x') };
	is($logger->messages()->[0]->{'level'}, '', 'stored under the empty name');
	is($out, "# $CLASS: no method ''\n", 'announced, with no warning (Test::Warnings checks)');
};

# ===========================================================================
# Invariants from the formal specification, checked only at the boundaries
# ===========================================================================

# Log: log' = log ^ <<entry>>, and nothing else changes
subtest 'Log: one entry added, nothing else changed' => sub {
	my $logger = quiet(level => $NAME_FOR{$MIDDLE});
	my %before = (verbose => $logger->verbose(), level => $logger->level(), lang => $logger->lang());
	foreach my $level (qw(emergency trace)) {	# the most and least severe
		my $count = $logger->count();
		$logger->$level('m');
		is($logger->count(), $count + 1, "$level: exactly one more entry");
		is($logger->messages()->[-1]->{'level'}, $level, "$level: added at the end");
	}
	is_deeply({ verbose => $logger->verbose(), level => $logger->level(), lang => $logger->lang() }, \%before, 'verbose, level and lang unchanged');
};

# Clear: log' = <>, and nothing else changes
subtest 'Clear: log emptied, nothing else changed' => sub {
	my $logger = quiet(lang => 'de', level => $NAME_FOR{$MOST_SEVERE});
	$logger->info('m');
	my %before = (verbose => $logger->verbose(), level => $logger->level(), lang => $logger->lang());
	$logger->clear();
	is($logger->count(), 0, 'empty');
	is_deeply({ verbose => $logger->verbose(), level => $logger->level(), lang => $logger->lang() }, \%before, 'settings unchanged');
};

# IsLevel: result = true <=> severity <= threshold; only the two values
# either side of each edge can tell <= from < or from >=
subtest 'IsLevel: true exactly when severity <= threshold' => sub {
	my $logger = quiet();
	foreach my $threshold ($MOST_SEVERE, $MIDDLE, $LEAST_SEVERE) {
		$logger->level($NAME_FOR{$threshold});
		foreach my $level (grep { abs($SEVERITY{$_} - $threshold) <= 1 } @PREDICATES) {
			my $method = "is_$level";
			my $want = ($SEVERITY{$level} <= $threshold) ? 1 : 0;
			is($logger->$method(), $want, "threshold $threshold, severity $SEVERITY{$level}: $want");
		}
	}
};

done_testing();
