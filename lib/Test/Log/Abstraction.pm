package Test::Log::Abstraction;

=encoding utf8

=head1 NAME

Test::Log::Abstraction - Capture log output in tests and assert on it

=head1 VERSION

0.002.0

=head1 SYNOPSIS

    use Test::Most;
    use Test::Log::Abstraction;

    my $logger = Test::Log::Abstraction->new();
    my $obj = Some::Class->new(logger => $logger);

    $obj->do_something();

    # Assertions on what was logged; each is a TAP test
    $logger->like(qr/updated/, 'do_something() logs that it updated');
    $logger->has_level('error', 'an error was logged');
    $logger->unlike(qr/fatal/, 'nothing fatal');
    is($logger->count(), 3, 'three messages');
    $logger->clear();

    # Or simply look at the messages
    diag($_->{'message'}) foreach @{ $logger->messages() };

=head1 DESCRIPTION

A test double for L<Log::Abstraction>, usable wherever code under test is
passed a C<< logger => >> object.

Every level method that L<Log::Abstraction> offers (C<trace>, C<debug>,
C<info>, C<notice>, C<warn>, C<error>, C<fatal>, C<critical>, C<alert> and
C<emergency>), plus the syslog spellings C<warning>, C<err>, C<crit>,
C<emerg>, C<panic> and C<informational>, records the message instead of
writing it anywhere, and optionally sends it to TAP diagnostics.  Nothing is
ever written to disk, and no logging backend is loaded.

The non-logging parts of the L<Log::Abstraction> API that code under test is
likely to call - C<level()>, the C<is_E<lt>levelE<gt>()> predicates,
C<messages()> and C<flush()> - are also implemented, so they are not
mistaken for unknown log levels.

=head2 Diagnostics

Messages at C<warning> and above are printed with L<Test::Builder/diag> by
default, so a test that accidentally triggers a warning is visible; C<trace>,
C<debug>, C<info> and C<notice> are printed only in verbose mode.  Verbose
mode is on when C<< verbose => 1 >> is passed to C<new()>, or when
C<$ENV{TEST_VERBOSE}> (set by C<prove -v>) or C<$ENV{VERBOSE}> is true.

Change it with the C<diag> option: C<'all'> prints everything,
C<'none'> prints nothing (unless verbose), a level name such as C<'error'>
prints that level and everything more severe, and an array reference prints
just those levels.

When an assertion (C<like>, C<unlike>, C<has_level>, C<empty>) fails, the
captured messages that explain the failure are printed as diagnostics, so
the reason is visible without re-running the test.

=head2 Language

The module's own messages (errors, warnings and failure diagnostics) are
available in English (C<en>), German (C<de>), French (C<fr>) and Simplified
Chinese (C<zh>).  The language is chosen, in order of precedence, from the
C<lang> option, the C<country> option (an ISO 3166 two-letter code), the
C<LC_ALL>, C<LC_MESSAGES> or C<LANG> environment variables when
C<< lang => 'auto' >>, and finally C<$Test::Log::Abstraction::config{lang}>
(C<en>).  English is the default, rather than the environment, so that test
output - and tests that match on it - are the same on every machine.
Missing translations fall back to English, key by key.  Templates can be
added or overridden with the C<i18n> option.

=head2 Configuration

Defaults live in the package hash C<%Test::Log::Abstraction::config>, a
flat hash of the same keys that C<new()> takes, so it can be filled from
L<Object::Configure> or set directly:

    $Test::Log::Abstraction::config{'diag'} = 'none';

=head2 Formal model

The formal specifications below share this state, in Z notation:

    [TEXT, NAME]
    BOOL ::= true | false
    LANG == { en, de, fr, zh }
    SEVERITY == 0 .. 7

    severity : NAME ⇸ SEVERITY

    Entry ≙ [ level : NAME; message : TEXT; fields : TEXT ⇸ TEXT ]

    Logger
      log       : seq Entry
      verbose   : BOOL
      threshold : SEVERITY
      lang      : LANG

C<severity> is the table of known level names: C<emergency>, C<emerg> and
C<panic> are 0; C<alert> 1; C<critical>, C<crit> and C<fatal> 2;
C<error> and C<err> 3; C<warning> and C<warn> 4; C<notice> 5; C<info> and
C<informational> 6; C<debug> and C<trace> 7.

=head2 Migrating from t/lib/MyLogger.pm

Replace, in each test file:

    use lib 't/lib';
    use MyLogger;
    ...
    logger => MyLogger->new()

with:

    use Test::Log::Abstraction;
    ...
    logger => Test::Log::Abstraction->new()

and delete F<t/lib/MyLogger.pm>.  Unlike the old MyLogger copies, this
implementation is identical everywhere, never recurses when a level method is
called with C<undef> (see F<t/autoload.t>), and records every message so
tests can assert on it instead of only printing it.

=cut

use 5.014;
use strict;
use warnings;
use autodie qw(:all);

use Carp qw(carp croak);
use Encode ();
use Params::Get qw(get_params);
use Params::Validate::Strict qw(validate_strict);
use Readonly;
use Scalar::Util ();
use Sub::Private ();
use Sub::Protected;
use Test::Builder ();

our $VERSION = '0.002.0';
our $AUTOLOAD;

# Routines that only this package may call.  Sub::Private's enforce mode is
# a process-wide setting, so it is localised here: only these names are
# wrapped, and any other module's choice of mode is left alone.  Wrapping
# happens at CHECK time (or at the end of this file when it is loaded at run
# time), by which point every sub named here has been compiled.
BEGIN {
	local $Sub::Private::config{'mode'} = 'enforce';
	Sub::Private->import(qw(
		_args _assert _at_level _build _clone _croak _diag_rule _diags
		_entry _explain _format _interpolate _matching _object _plural _record
		_resolve_lang _stringify _template _validate _variant
	));
}

# Defaults for new(); a flat hash so Object::Configure, or a test, can
# override any of them before loggers are created
our %config = (
	diag => 'warning',	# print this level and more severe by default
	lang => 'en',	# deterministic output unless asked otherwise
	level => 'trace',	# threshold reported by level() and is_*()
);

# Level -> severity, lower is more severe, following POSIX syslog priorities.
# trace and debug share a severity, as they do in Log::Abstraction
Readonly::Hash my %SEVERITY => (
	emergency => 0,
	emerg => 0,
	panic => 0,
	alert => 1,
	critical => 2,
	crit => 2,
	fatal => 2,
	error => 3,
	err => 3,
	warning => 4,
	warn => 4,
	notice => 5,
	info => 6,
	informational => 6,
	debug => 7,
	trace => 7,
);

# The levels that Log::Abstraction has is_<level>() predicates for
Readonly::Array my @PREDICATES => qw(trace debug info notice warn error critical alert emergency);

# diag option values that are not level names
Readonly::Scalar my $DIAG_ALL => 'all';
Readonly::Scalar my $DIAG_NONE => 'none';

# lang option value that means "read the POSIX locale variables"
Readonly::Scalar my $LANG_AUTO => 'auto';

# Catalogue used when a key has no translation in the chosen language
Readonly::Scalar my $FALLBACK_LANG => 'en';

# Locale environment variables, most specific first, as POSIX defines them
Readonly::Array my @LOCALE_VARS => qw(LC_ALL LC_MESSAGES LANG);

# How many captured messages a failing assertion lists before summarising
Readonly::Scalar my $MAX_EXPLAIN => 20;

# Shown in place of a reference that contains itself, so rendering a
# self-referential structure cannot recurse forever
Readonly::Scalar my $CYCLE => '(cycle)';

# ISO 3166 country code -> catalogue language
Readonly::Hash my %COUNTRY_LANG => (
	AT => 'de', AU => 'en', BE => 'fr', CA => 'en', CH => 'de',
	CN => 'zh', DE => 'de', FR => 'fr', GB => 'en', HK => 'zh',
	IE => 'en', LU => 'fr', NZ => 'en', SG => 'zh', TW => 'zh',
	UK => 'en', US => 'en',
);

# CLDR plural categories per language; 'zero' is not a CLDR category for
# these languages, so templates may add it as an explicit "=0" case
Readonly::Hash my %PLURAL => (
	en => sub { ($_[0] == 1) ? 'one' : 'other' },
	de => sub { ($_[0] == 1) ? 'one' : 'other' },
	fr => sub { ($_[0] < 2) ? 'one' : 'other' },	# French counts 0 as singular
	zh => sub { 'other' },	# Chinese has no grammatical plural
);

# Message catalogues.  Templates use %{name}s-style placeholders (any sprintf
# conversion may follow the name), and may be a hash keyed by gender or by
# plural category instead of a string; see i18n().  Non-English text is
# written with \x{} escapes to keep this source file ASCII.
Readonly::Hash my %MESSAGES => (
	en => {
		class_invocant => '%{class}s: %{method}s() must be called on an object, not on the class',
		invalid_argument => '%{class}s: invalid argument: %{reason}s',
		invalid_diag_level => q{%{class}s: invalid diag level '%{level}s'},
		invalid_diag_type => '%{class}s: diag must be a level name, "all", "none" or an array reference of level names',
		invalid_level => q{%{class}s: invalid syslog level '%{level}s'},
		needs_level => '%{class}s: %{method}s() needs a level name',
		needs_pattern => '%{class}s: %{method}s() needs a pattern',
		no_method => q{%{class}s: no method '%{method}s'},
		captured => {
			zero => '%{class}s: no messages were captured',
			one => '%{class}s: %{count}d message was captured:',
			other => '%{class}s: %{count}d messages were captured:',
		},
		matched => {
			one => '%{class}s: %{count}d message matched:',
			other => '%{class}s: %{count}d messages matched:',
		},
		entry => '    [%{level}s] %{message}s',
		truncated => '    ... and %{count}d more',
	},
	de => {
		class_invocant => '%{class}s: %{method}s() muss an einem Objekt aufgerufen werden, nicht an der Klasse',
		invalid_argument => "%{class}s: ung\x{fc}ltiges Argument: %{reason}s",
		invalid_diag_level => "%{class}s: ung\x{fc}ltige diag-Stufe '%{level}s'",
		invalid_diag_type => '%{class}s: diag muss ein Stufenname, "all", "none" oder eine Array-Referenz von Stufennamen sein',
		invalid_level => "%{class}s: ung\x{fc}ltige Syslog-Stufe '%{level}s'",
		needs_level => "%{class}s: %{method}s() ben\x{f6}tigt einen Stufennamen",
		needs_pattern => "%{class}s: %{method}s() ben\x{f6}tigt ein Muster",
		no_method => q{%{class}s: keine Methode '%{method}s'},
		captured => {
			zero => '%{class}s: es wurden keine Meldungen erfasst',
			one => '%{class}s: %{count}d Meldung wurde erfasst:',
			other => '%{class}s: %{count}d Meldungen wurden erfasst:',
		},
		matched => {
			one => '%{class}s: %{count}d Meldung passte:',
			other => '%{class}s: %{count}d Meldungen passten:',
		},
		truncated => '    ... und %{count}d weitere',
	},
	fr => {
		class_invocant => "%{class}s : %{method}s() doit \x{ea}tre appel\x{e9}e sur un objet, pas sur la classe",
		invalid_argument => '%{class}s : argument invalide : %{reason}s',
		invalid_diag_level => q{%{class}s : niveau diag invalide '%{level}s'},
		invalid_diag_type => "%{class}s : diag doit \x{ea}tre un nom de niveau, \"all\", \"none\" ou une r\x{e9}f\x{e9}rence de tableau de noms de niveaux",
		invalid_level => q{%{class}s : niveau syslog invalide '%{level}s'},
		needs_level => "%{class}s : %{method}s() n\x{e9}cessite un nom de niveau",
		needs_pattern => "%{class}s : %{method}s() n\x{e9}cessite un motif",
		no_method => "%{class}s : aucune m\x{e9}thode '%{method}s'",
		captured => {
			zero => "%{class}s : aucun message n'a \x{e9}t\x{e9} captur\x{e9}",
			one => "%{class}s : %{count}d message a \x{e9}t\x{e9} captur\x{e9} :",
			other => "%{class}s : %{count}d messages ont \x{e9}t\x{e9} captur\x{e9}s :",
		},
		matched => {
			one => '%{class}s : %{count}d message correspond :',
			other => '%{class}s : %{count}d messages correspondent :',
		},
		truncated => '    ... et %{count}d de plus',
	},
	zh => {
		# "must be called on an object, not on the class"
		class_invocant => "%{class}s\x{ff1a}%{method}s() \x{5fc5}\x{987b}\x{5728}\x{5bf9}\x{8c61}\x{4e0a}\x{8c03}\x{7528}\x{ff0c}\x{800c}\x{4e0d}\x{662f}\x{5728}\x{7c7b}\x{4e0a}\x{8c03}\x{7528}",
		# "invalid argument"
		invalid_argument => "%{class}s\x{ff1a}\x{65e0}\x{6548}\x{7684}\x{53c2}\x{6570}\x{ff1a}%{reason}s",
		# "invalid diag level"
		invalid_diag_level => "%{class}s\x{ff1a}\x{65e0}\x{6548}\x{7684} diag \x{7ea7}\x{522b} '%{level}s'",
		# "diag must be a level name, all, none or an array reference of level names"
		invalid_diag_type => "%{class}s\x{ff1a}diag \x{5fc5}\x{987b}\x{662f}\x{7ea7}\x{522b}\x{540d}\x{79f0}\x{3001}\"all\"\x{3001}\"none\" \x{6216}\x{7ea7}\x{522b}\x{540d}\x{79f0}\x{7684}\x{6570}\x{7ec4}\x{5f15}\x{7528}",
		# "invalid syslog level"
		invalid_level => "%{class}s\x{ff1a}\x{65e0}\x{6548}\x{7684} syslog \x{7ea7}\x{522b} '%{level}s'",
		# "needs a level name"
		needs_level => "%{class}s\x{ff1a}%{method}s() \x{9700}\x{8981}\x{4e00}\x{4e2a}\x{7ea7}\x{522b}\x{540d}\x{79f0}",
		# "needs a pattern"
		needs_pattern => "%{class}s\x{ff1a}%{method}s() \x{9700}\x{8981}\x{4e00}\x{4e2a}\x{6a21}\x{5f0f}",
		# "no method"
		no_method => "%{class}s\x{ff1a}\x{6ca1}\x{6709}\x{65b9}\x{6cd5} '%{method}s'",
		captured => {
			# "no messages were captured"
			zero => "%{class}s\x{ff1a}\x{6ca1}\x{6709}\x{6355}\x{83b7}\x{5230}\x{4efb}\x{4f55}\x{6d88}\x{606f}",
			# "captured N messages"
			other => "%{class}s\x{ff1a}\x{6355}\x{83b7}\x{4e86} %{count}d \x{6761}\x{6d88}\x{606f}\x{ff1a}",
		},
		# "N messages matched"
		matched => {
			other => "%{class}s\x{ff1a}%{count}d \x{6761}\x{6d88}\x{606f}\x{5339}\x{914d}\x{ff1a}",
		},
		# "... N more"
		truncated => "    \x{2026}\x{2026}\x{8fd8}\x{6709} %{count}d \x{6761}",
	},
);

# Schema for new()'s options.  diag is not listed: _diag_rule() validates it,
# because its messages say what a valid diag is, which a type error cannot
Readonly::Hash my %NEW_SCHEMA => (
	verbose => { type => 'scalar', optional => 1 },
	level => { type => 'string', optional => 1 },
	lang => { type => 'string', optional => 1, matches => qr/\A(?:auto|[A-Za-z]{2,3}(?:[_.\@-][\w.\@-]*)?)\z/ },
	country => { type => 'string', optional => 1, matches => qr/\A[A-Za-z]{2}\z/ },
	i18n => { type => 'hashref', optional => 1 },
);

# Schema shared by like() and unlike()
Readonly::Hash my %PATTERN_SCHEMA => (
	pattern => { type => ['regex', 'string'] },
	name => { type => 'string', optional => 1 },
);

# Schema for has_level()
Readonly::Hash my %LEVEL_SCHEMA => (
	level => { type => 'string' },
	name => { type => 'string', optional => 1 },
);

=head1 METHODS

=head2 new

Creates a logger.

=head3 Purpose

Build a test double that captures everything logged to it.

=head3 Args

All optional, as a hash or a hash reference:

=over 4

=item * C<verbose> - true to print every message.  Defaults to
C<$ENV{TEST_VERBOSE} || $ENV{VERBOSE}>.

=item * C<diag> - which messages to print: C<'all'>, C<'none'>, a level
name (that level and more severe), or an array reference of level names.
Defaults to C<'warning'>.

=item * C<level> - the threshold that C<level()> and C<is_E<lt>levelE<gt>()>
report.  Defaults to C<'trace'>, so all C<is_*> predicates are true and the
code under test exercises its debug paths.  It does not filter capture.

=item * C<lang> - language of this module's own messages, or C<'auto'> to
read C<LC_ALL>, C<LC_MESSAGES> and C<LANG>.

=item * C<country> - ISO 3166 two-letter country code used to choose the
language when C<lang> is not given; case-insensitive.

=item * C<i18n> - C<< { lang => { key => template } } >> to add or override
message templates (see L</i18n>).

=back

Any other options are accepted and ignored, as L<Log::Abstraction/new>
takes a configuration hash that the double does not need.  An odd-length
argument list is ignored rather than fatal, for compatibility with the
MyLogger copies this module replaces.

Called on an existing logger, it makes a clone: the same options, overridden
by any passed, the current C<verbose> and C<level> settings, and a copy of
the captured messages, as L<Log::Abstraction/new> does.  It may also be
called as a function, C<Test::Log::Abstraction::new(%options)>.

=head3 Returns

The new logger.

=head3 Side Effects

Reads C<%ENV> for verbosity and, with C<< lang => 'auto' >>, the locale.

=head3 EXAMPLE

    my $logger = Test::Log::Abstraction->new();
    my $quiet = Test::Log::Abstraction->new(diag => 'none');
    my $german = Test::Log::Abstraction->new({ country => 'DE' });
    my $clone = $logger->new(diag => 'all');

=head3 API SPECIFICATION

=head4 Input

    {
        verbose => { type => 'scalar', optional => 1 },
        diag => { type => ['string', 'arrayref'], optional => 1 },
        level => { type => 'string', optional => 1 },
        lang => { type => 'string', optional => 1 },
        country => { type => 'string', optional => 1, matches => qr/\A[A-Za-z]{2}\z/ },
        i18n => { type => 'hashref', optional => 1 },
    }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    invalid diag level 'X'          X is not a level name       Use a name from the level list
    diag must be a level name ...   diag is a hash or code ref  Pass a string or an array ref
    invalid syslog level 'X'        level option is unknown     Use a name from the level list
    invalid argument: ...           an option has the wrong     Fix the option's type or value
                                    type or format

All are fatal (C<croak>).

=head3 FORMAL SPECIFICATION

    New
      Logger'
      verbose? : BOOL
      level? : NAME
      lang? : LANG
      ─────────
      level? ∈ dom severity
      log' = ⟨⟩
      verbose' = verbose?
      threshold' = severity level?
      lang' = lang?

    Clone
      ΞLogger
      Logger'
      ─────────
      log' = log
      verbose' = verbose ∧ threshold' = threshold

=head3 PSEUDOCODE

    if called on an object:
        options = object's options + overrides
        build a new logger from options with a copy of the messages
        copy verbose and level unless overridden
    else:
        if called as a function, treat the first argument as an option
        normalise the arguments to a hash, ignoring an odd list
        validate the options
        resolve the language, then the diag rule and the level
    return the logger

=cut

sub new {
	my ($class, @args) = @_;

	# Clone form: $logger->new(%overrides), as in Log::Abstraction
	return $class->_clone(_args(\@args)) if(Scalar::Util::blessed($class));

	# Function-call form, Test::Log::Abstraction::new(...): whatever was
	# passed first is an option, not a class name
	if(!defined($class) || ref($class) || !UNIVERSAL::isa($class, __PACKAGE__)) {
		unshift @args, $class if(defined($class));
		$class = __PACKAGE__;
	}

	return $class->_build(_args(\@args), []);
}

# _args - normalise constructor arguments to a hash reference
#
# Purpose:      Accept every argument shape used across the tests that this
#               module replaces MyLogger in.
# Entry:        $args - array reference of what the caller passed after the
#               class or invocant.
# Exit:         Returns a new hash reference; empty for no arguments or for
#               an odd-length list that is not a single hash reference.
# Side effects: None.  The caller's hash is copied, never kept.
sub _args {
	my $args = shift;

	# Params::Get croaks on an odd list; a stray argument must not break a
	# test run, so only hand it shapes that it accepts
	my $usable = ((@{$args} == 1) && (ref($args->[0]) eq 'HASH')) || (@{$args} && !(@{$args} % 2));
	my $params = $usable ? get_params(undef, $args) : undef;

	return { %{$params || {}} };
}

# _build - construct a logger from validated options
#
# Purpose:      The one place a logger's state is set up, shared by new()
#               and _clone() so the two cannot drift apart.
# Entry:        $class    - package to bless into.
#               $options  - hash reference from _args().
#               $messages - array reference of entries to start with.
# Exit:         Returns the blessed logger.
# Side effects: Reads %ENV.  Croaks, in the logger's language, on an
#               invalid option.
sub _build {
	my ($class, $options, $messages) = @_;

	# Keep diag aside: _diag_rule() gives it a better message than a schema
	my $valid = $class->_validate(\%NEW_SCHEMA, $options);
	$valid->{'diag'} = $options->{'diag'} if(exists($options->{'diag'}));

	# Internal state is kept apart from options, so no option name can
	# overwrite it (an option called 'messages' once replaced the capture)
	my $self = bless {
		messages => $messages,
		options => $valid,
		verbose => exists($valid->{'verbose'}) ? ($valid->{'verbose'} ? 1 : 0) : (($ENV{'TEST_VERBOSE'} || $ENV{'VERBOSE'}) ? 1 : 0),
	}, $class;

	# The language first, so that the checks below report in it
	$self->{'lang'} = _resolve_lang($valid);
	$self->{'diag_rule'} = $self->_diag_rule(exists($valid->{'diag'}) ? $valid->{'diag'} : $config{'diag'});

	# An unknown level at construction is a programming error, so fatal;
	# level() only carps, as Log::Abstraction's does
	my $level = lc(defined($valid->{'level'}) ? $valid->{'level'} : $config{'level'});
	$self->_croak('invalid_level', { level => $level }) if(!exists($SEVERITY{$level}));
	$self->{'level'} = $SEVERITY{$level};

	return $self;
}

# _clone - copy a logger, as Log::Abstraction->new does on an object
#
# Purpose:      Clone with overrides, re-validating everything so that, for
#               example, a new diag option really changes the diag rule.
# Entry:        $self      - logger to copy.
#               $overrides - hash reference of options to change.
# Exit:         Returns the clone.
# Side effects: None on $self; entries are copied so that neither logger can
#               alter the other's history.
sub _clone {
	my ($self, $overrides) = @_;

	my $copy = [ map { +{ %{$_} } } @{$self->{'messages'}} ];
	my $clone = ref($self)->_build({ %{$self->{'options'}}, %{$overrides} }, $copy);

	# Runtime changes made with verbose() and level() carry over, unless the
	# caller asked for something else
	$clone->{'verbose'} = $self->{'verbose'} if(!exists($overrides->{'verbose'}));
	$clone->{'level'} = $self->{'level'} if(!exists($overrides->{'level'}));

	return $clone;
}

# _validate - check arguments against a Params::Validate::Strict schema
#
# Purpose:      Run validate_strict, reporting failures through i18n so the
#               message is in the logger's language and blames the caller.
# Entry:        $self   - logger or class name.
#               $schema - schema hash reference.
#               $input  - hash reference of arguments.
# Exit:         Returns the validated hash reference; unknown keys dropped.
# Side effects: Croaks with 'invalid_argument' on failure.
sub _validate {
	my ($self, $schema, $input) = @_;

	my $valid;
	if(!eval { $valid = validate_strict(schema => $schema, input => $input, unknown_parameter_handler => 'ignore'); 1 }) {
		# Keep the validator's explanation, but not its file and line,
		# which point inside Params::Validate::Strict, not at the caller
		(my $reason = $@) =~ s/\A.*?validate_strict:\s*//s;
		$reason =~ s/\s+at \S+ line \d+\.?\s*\z//s;
		$self->_croak('invalid_argument', { reason => $reason });
	}

	return $valid || {};
}

# _resolve_lang - choose the catalogue for a logger's own messages
#
# Purpose:      Apply the documented precedence: lang, country, the POSIX
#               locale variables (only for lang => 'auto'), then %config.
# Entry:        $options - validated options hash reference.
# Exit:         Returns a language tag that has a catalogue (built in, or
#               supplied with the i18n option); otherwise $FALLBACK_LANG.
# Side effects: Reads %ENV when the language is 'auto'.
sub _resolve_lang {
	my $options = shift;

	my $wanted = defined($options->{'lang'}) ? $options->{'lang'} : $config{'lang'};
	my $tag;
	if(defined($options->{'lang'}) && (lc($options->{'lang'}) ne $LANG_AUTO)) {
		$tag = $options->{'lang'};
	} elsif(defined($options->{'country'})) {
		# exists() first: a Readonly hash croaks on autovivification
		my $country = uc($options->{'country'});
		$tag = exists($COUNTRY_LANG{$country}) ? $COUNTRY_LANG{$country} : $FALLBACK_LANG;
	} elsif(lc($wanted) eq $LANG_AUTO) {
		# The first set variable wins, as in POSIX setlocale()
		($tag) = grep { defined($_) && length($_) } map { $ENV{$_} } @LOCALE_VARS;
	} else {
		$tag = $wanted;
	}

	# 'de_DE.UTF-8' -> 'de'; the C and POSIX locales are English
	my ($lang) = (lc(defined($tag) ? $tag : '') =~ /\A([a-z]{2,3})(?![a-z])/);
	my $known = defined($lang) && (exists($MESSAGES{$lang}) || ($options->{'i18n'} && $options->{'i18n'}->{$lang}));

	return $known ? $lang : $FALLBACK_LANG;
}

# _diag_rule - normalise the diag option into an internal rule
#
# Purpose:      Validate the diag option once, at construction time.
# Entry:        $self - the logger being built (for its language).
#               $spec - 'all', 'none', a level name, or an array reference
#               of level names.
# Exit:         Returns { all => 1 }, { levels => {...} },
#               { threshold => $severity }, or {} for 'none'.
# Side effects: Croaks on anything unrecognised: a silent typo in a test's
#               diag option would otherwise hide log output forever.
sub _diag_rule {
	my ($self, $spec) = @_;

	$spec = $config{'diag'} if(!defined($spec));

	if(ref($spec) eq 'ARRAY') {
		my %levels;
		foreach my $level (@{$spec}) {
			my $name = defined($level) ? lc($level) : 'undef';
			$self->_croak('invalid_diag_level', { level => defined($level) ? $level : 'undef' }) if(!exists($SEVERITY{$name}));
			$levels{$name} = 1;
		}
		return { levels => \%levels };
	}

	$self->_croak('invalid_diag_type') if(ref($spec));

	return {} if($spec eq $DIAG_NONE);
	return { all => 1 } if($spec eq $DIAG_ALL);
	$self->_croak('invalid_diag_level', { level => $spec }) if(!exists($SEVERITY{lc($spec)}));

	return { threshold => $SEVERITY{lc($spec)} };
}

=head2 trace, debug, info, notice, warn, error, fatal, critical, alert, emergency

Record a message at that level.

=head3 Purpose

Every L<Log::Abstraction> level, and the syslog spellings C<warning>, C<err>,
C<crit>, C<emerg>, C<panic> and C<informational>, is a method that records
the call and, subject to the C<diag> setting, prints it.

=over 4

=item * C<trace>, C<debug>, C<info>, C<informational>, C<notice>

Captured; printed only in verbose mode by default.

=item * C<warn>, C<warning>, C<error>, C<err>, C<critical>, C<crit>,
C<fatal>, C<alert>, C<emergency>, C<emerg>, C<panic>

Captured and printed by default.

=back

=head3 Args

Following L<Log::Abstraction>'s rules: the arguments are concatenated into
the message and a trailing newline removed; a single array reference is a
list of message parts; a hash reference at the end of two or more arguments
is captured, copied, as structured C<fields> (an empty one is dropped).
Unlike L<Log::Abstraction>, a lone hash reference is rendered as sorted
C<< {key => value} >> pairs and nested array references as C<[a, b]>, so
they can be matched, and C<undef> becomes the string C<undef> instead of
being dropped, so that it is visible.

=head3 Returns

The logger, as L<Log::Abstraction> does, so calls can be chained.

=head3 Side Effects

Appends one entry to C<messages()>; may print a diagnostic.  C<$@> and
C<$!> are preserved, so logging inside an error handler cannot change the
error being handled.

=head3 EXAMPLE

    $logger->warn('something looks wrong');
    $logger->info('started', { pid => $$ });
    $logger->error({ error => 'cannot open file' });
    $logger->debug(['part 1, ', 'part 2']);

=head3 API SPECIFICATION

=head4 Input

    { type => 'arrayref', optional => 1 }    # any list of values

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    X() must be called on an        called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Log
      ΔLogger
      name? : NAME
      text? : TEXT
      ─────────
      name? ∈ dom severity
      log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩
      verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang

=cut

# Generate the level methods.  Each is a thin wrapper over _record, and they
# exist as real methods so that AUTOLOAD only sees genuinely unknown names
foreach my $level (keys %SEVERITY) {
	no strict 'refs';	## no critic (ProhibitNoStrict)
	*{$level} = sub {
		my $self = shift;
		return $self->_object($level)->_record($level, \@_);
	};
}

=head2 is_trace, is_debug, is_info, is_notice, is_warn, is_error, is_critical, is_alert, is_emergency

Whether a level is enabled.

=head3 Purpose

Mirror L<Log::Abstraction>'s predicates, so that code which guards an
expensive log call with C<< if($logger->is_debug()) >> runs that call under
test.

=head3 Args

None.

=head3 Returns

1 if the threshold set with C<level> admits that level, else 0.  With the
default threshold, C<trace>, every predicate is 1.

=head3 Side Effects

None.

=head3 EXAMPLE

    $logger->level('warning');
    $logger->is_warn();    # 1
    $logger->is_info();    # 0

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    X() must be called on an        called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    IsLevel
      ΞLogger
      name? : NAME
      result! : BOOL
      ─────────
      result! = true ⇔ threshold ≥ severity name?

=cut

foreach my $level (@PREDICATES) {
	my $method = "is_$level";
	no strict 'refs';	## no critic (ProhibitNoStrict)
	*{$method} = sub {
		my $self = shift;
		return ($self->_object($method)->{'level'} >= $SEVERITY{$level}) ? 1 : 0;
	};
}

# _object - insist on an object invocant
#
# Purpose:      Turn a class-method call such as
#               Test::Log::Abstraction->warn() into a clear error, rather
#               than Perl's "Can't use string as a HASH ref".
# Entry:        $self   - the invocant.
#               $method - the public method's name, for the message.
# Exit:         Returns $self, for chaining.
# Side effects: Croaks with 'class_invocant' if $self is not an object.
sub _object {
	my ($self, $method) = @_;

	$self->_croak('class_invocant', { method => $method }) if(!Scalar::Util::blessed($self));

	return $self;
}

# _record - capture one logged message
#
# Purpose:      The single place every level method ends up.
# Entry:        $self  - this logger.
#               $level - level name as called by the code under test.
#               $args  - array reference of the log call's arguments.
# Exit:         Returns $self, for chaining.
# Side effects: Pushes an entry onto the capture and prints it when the
#               diag rule allows.  Localises $@ and $! so that the caller's
#               error state survives, as Log::Abstraction does.
sub _record {
	my ($self, $level, $args) = @_;

	local ($@, $!);
	my $entry = _entry(lc($level), $args);
	push @{$self->{'messages'}}, $entry;
	$self->_emit($entry->{'message'}) if($self->_diags($entry->{'level'}));

	return $self;
}

# _entry - turn a log call's arguments into a captured entry
#
# Purpose:      Mirror Log::Abstraction's argument handling, but render
#               references readably instead of as HASH(0x...).
# Entry:        $level - lower-cased level name.
#               $args  - array reference of the arguments.
# Exit:         Returns { level, message } plus 'fields' when a non-empty
#               hash reference followed one or more other arguments.
# Side effects: None; the caller's arrays and hashes are not modified, and
#               the fields hash is copied so that later changes to it by the
#               caller cannot rewrite the captured history.
sub _entry {
	my ($level, $args) = @_;

	my @args = @{$args};
	my $entry = { level => $level };

	# A trailing plain hash after the message is structured fields
	if((@args >= 2) && (ref($args[-1]) eq 'HASH')) {
		my $fields = pop @args;
		$entry->{'fields'} = { %{$fields} } if(%{$fields});
	}

	# A lone array reference is a list of message parts
	@args = @{$args[0]} if((@args == 1) && (ref($args[0]) eq 'ARRAY'));

	my $message = join('', map { _stringify($_, {}) } @args);
	chomp($message);
	$entry->{'message'} = $message;

	return $entry;
}

# _stringify - render any value as a readable string
#
# Purpose:      Stringify log arguments without warnings or fatals.
# Entry:        $value - scalar, undef, or any reference.
#               $seen  - hash reference of reference addresses being
#               rendered further up this call chain.
# Exit:         Returns a string: 'undef' for undef, '{k => v}' for a plain
#               hash, '[a, b]' for a plain array, $CYCLE for a reference
#               that contains itself, and Perl's normal stringification
#               otherwise (objects honour overloading).
# Side effects: None.  $seen is restored on return.
sub _stringify {
	my ($value, $seen) = @_;

	return 'undef' if(!defined($value));

	# Plain scalars, objects and other reference types: Perl's own form
	my $type = ref($value);
	return "$value" if(($type ne 'HASH') && ($type ne 'ARRAY'));

	# A structure that contains itself would otherwise recurse forever
	my $address = Scalar::Util::refaddr($value);
	return $CYCLE if($seen->{$address});
	local $seen->{$address} = 1;

	return '{' . join(', ', map { "$_ => " . _stringify($value->{$_}, $seen) } sort keys %{$value}) . '}' if($type eq 'HASH');

	return '[' . join(', ', map { _stringify($_, $seen) } @{$value}) . ']';
}

# _diags - should this level be printed?
#
# Purpose:      One decision per message, from the diag rule and verbosity.
# Entry:        $self  - this logger.
#               $level - the lower-cased level name.
# Exit:         Returns 1 if the message should go to TAP diagnostics, else 0.
# Side effects: None.  An unknown level has no severity, so a threshold rule
#               never prints it; AUTOLOAD prints its own notice for those.
sub _diags {
	my ($self, $level) = @_;

	my $rule = $self->{'diag_rule'};

	# Verbose or 'all' print everything; a list prints just its levels; a
	# threshold prints known levels at least that severe
	my $listed = $rule->{'levels'} && $rule->{'levels'}->{$level};
	my $severe = defined($rule->{'threshold'}) && exists($SEVERITY{$level}) && ($SEVERITY{$level} <= $rule->{'threshold'});

	return ($self->{'verbose'} || $rule->{'all'} || $listed || $severe) ? 1 : 0;
}

=head2 AUTOLOAD

Catch calls to methods that do not exist.

=head3 Purpose

Any other method call - typically a level name that does not exist, such as
a typo - captures the message under that name and prints a notice that the
diag setting cannot suppress, instead of dying part way through a test.  A
typo'd level therefore cannot pass silently.

=head3 Args

As for a level method.

=head3 Returns

The logger.

=head3 Side Effects

Records an entry with the called name as its level, and prints
C<no method 'name'>.

=head3 EXAMPLE

    $logger->wran('oops');    # captured as level 'wran', notice printed

=head3 API SPECIFICATION

=head4 Input

    { type => 'arrayref', optional => 1 }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    no method 'X'                   X is not a method or level  Fix the method name
    X() must be called on an        unknown class method        Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Unknown
      ΔLogger
      name? : NAME
      text? : TEXT
      ─────────
      name? ∉ dom severity
      log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩

=cut

sub AUTOLOAD {
	my ($self, @args) = @_;

	my ($name) = ($AUTOLOAD =~ /::(\w+)\z/);
	$self->_object($name)->_record($name, \@args);

	return $self->_emit($self->i18n('no_method', { method => $name }));
}

# Defined so that object destruction never reaches AUTOLOAD
sub DESTROY { }

=head2 messages

The captured messages.

=head3 Purpose

Let a test inspect everything that was logged.

=head3 Args

None.

=head3 Returns

A reference to a new array of C<< { level, message } >> hash references, in
the order they were logged; entries logged with structured fields also have
a C<fields> hash reference.  The array is a copy, as in
L<Log::Abstraction>, so changing it does not change the capture.

=head3 Side Effects

None.

=head3 EXAMPLE

    foreach my $entry (@{ $logger->messages() }) {
        diag("$entry->{level}: $entry->{message}");
    }

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'arrayref' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    messages() must be called on    called on the class name    Call it on a logger object
    an object, not on the class

=head3 FORMAL SPECIFICATION

    Messages
      ΞLogger
      result! : seq Entry
      ─────────
      result! = log

=cut

sub messages {
	my $self = shift;

	return [ @{$self->_object('messages')->{'messages'}} ];
}

=head2 clear

Forget the captured messages.

=head3 Purpose

Reset between phases of a test.

=head3 Args

None.

=head3 Returns

The logger, for chaining.

=head3 Side Effects

Empties the capture.

=head3 EXAMPLE

    $logger->clear()->empty('nothing logged yet');

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    clear() must be called on an    called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Clear
      ΔLogger
      ─────────
      log' = ⟨⟩
      verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang

=cut

sub clear {
	my $self = shift;

	@{$self->_object('clear')->{'messages'}} = ();

	return $self;
}

=head2 count

How many messages were captured.

=head3 Purpose

Assert on the volume of logging.

=head3 Args

=over 4

=item * C<$level> - optional; count only that level (case-insensitive).
Aliases are distinct: C<count('warn')> does not count C<warning> calls.

=back

=head3 Returns

The number of matching messages.

=head3 Side Effects

None.

=head3 EXAMPLE

    is($logger->count(), 3, 'three messages');
    is($logger->count('error'), 1, 'one error');

=head3 API SPECIFICATION

=head4 Input

    { level => { type => 'string', optional => 1 } }

=head4 Output

    { type => 'integer', min => 0 }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    count() must be called on an    called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Count
      ΞLogger
      level? : NAME
      result! : ℕ
      ─────────
      result! = # (log ↾ { e : Entry | e.level = level? })

=cut

sub count {
	my ($self, $level) = @_;

	my $messages = $self->_object('count')->{'messages'};

	return defined($level) ? scalar(@{$self->_at_level($level)}) : scalar(@{$messages});
}

=head2 like

Assert that a message matches.

=head3 Purpose

Pass if any captured message matches the pattern.

=head3 Args

=over 4

=item * C<$pattern> - a C<qr//> or a string, used as a regular expression.

=item * C<$name> - optional test name.

=back

=head3 Returns

The test result.

=head3 Side Effects

Reports a test through L<Test::Builder>, so count it in your plan (or use
C<done_testing()>).  On failure, lists the captured messages as
diagnostics.

=head3 EXAMPLE

    $logger->like(qr/updated/, 'the update was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        pattern => { type => ['regex', 'string'] },
        name => { type => 'string', optional => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    like() needs a pattern          no pattern was given        Pass a qr// or a string
    invalid argument: ...           pattern is not a regex      Pass a qr// or a string
                                    or a string
    N messages were captured:       (diagnostic) the test       Compare the listed messages
                                    failed                      with the pattern

=head3 FORMAL SPECIFICATION

    Like
      ΞLogger
      pattern? : ℙ TEXT
      result! : BOOL
      ─────────
      result! = true ⇔ (∃ e : ran log • e.message ∈ pattern?)

=cut

sub like {
	my ($self, $pattern, $name) = @_;

	$self->_object('like');
	$self->_croak('needs_pattern', { method => 'like' }) if(!defined($pattern));
	my $valid = $self->_validate(\%PATTERN_SCHEMA, { pattern => $pattern, (defined($name) ? (name => $name) : ()) });

	return $self->_assert(scalar(@{$self->_matching($valid->{'pattern'})}), $name, 'captured', $self->{'messages'});
}

=head2 unlike

Assert that no message matches.

=head3 Purpose

Pass if no captured message matches the pattern.

=head3 Args

=over 4

=item * C<$pattern> - a C<qr//> or a string, used as a regular expression.

=item * C<$name> - optional test name.

=back

=head3 Returns

The test result.

=head3 Side Effects

Reports a test through L<Test::Builder>.  On failure, lists the messages
that matched as diagnostics.

=head3 EXAMPLE

    $logger->unlike(qr/fatal/, 'nothing fatal was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        pattern => { type => ['regex', 'string'] },
        name => { type => 'string', optional => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    unlike() needs a pattern        no pattern was given        Pass a qr// or a string
    invalid argument: ...           pattern is not a regex      Pass a qr// or a string
                                    or a string
    N messages matched:             (diagnostic) the test       Look at the listed messages
                                    failed

=head3 FORMAL SPECIFICATION

    Unlike
      ΞLogger
      pattern? : ℙ TEXT
      result! : BOOL
      ─────────
      result! = true ⇔ (∀ e : ran log • e.message ∉ pattern?)

=cut

sub unlike {
	my ($self, $pattern, $name) = @_;

	$self->_object('unlike');
	$self->_croak('needs_pattern', { method => 'unlike' }) if(!defined($pattern));
	my $valid = $self->_validate(\%PATTERN_SCHEMA, { pattern => $pattern, (defined($name) ? (name => $name) : ()) });
	my $matches = $self->_matching($valid->{'pattern'});

	return $self->_assert(!@{$matches}, $name, 'matched', $matches);
}

=head2 has_level

Assert that a level was logged.

=head3 Purpose

Pass if at least one message was logged at that level.

=head3 Args

=over 4

=item * C<$level> - level name, case-insensitive.  Aliases are distinct:
C<has_level('warn')> does not see C<warning> calls.

=item * C<$name> - optional test name.

=back

=head3 Returns

The test result.

=head3 Side Effects

Reports a test through L<Test::Builder>.  On failure, lists the captured
messages as diagnostics.

=head3 EXAMPLE

    $logger->has_level('error', 'the failure was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        level => { type => 'string' },
        name => { type => 'string', optional => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    has_level() needs a level name  no level was given          Pass a level name
    invalid argument: ...           level is not a string       Pass a level name
    N messages were captured:       (diagnostic) the test       Look at the listed levels
                                    failed

=head3 FORMAL SPECIFICATION

    HasLevel
      ΞLogger
      level? : NAME
      result! : BOOL
      ─────────
      result! = true ⇔ (∃ e : ran log • e.level = level?)

=cut

sub has_level {
	my ($self, $level, $name) = @_;

	$self->_object('has_level');
	$self->_croak('needs_level', { method => 'has_level' }) if(!defined($level));
	my $valid = $self->_validate(\%LEVEL_SCHEMA, { level => $level, (defined($name) ? (name => $name) : ()) });

	return $self->_assert(scalar(@{$self->_at_level($valid->{'level'})}), $name, 'captured', $self->{'messages'});
}

=head2 empty

Assert that nothing was logged.

=head3 Purpose

The usual assertion after a clean run.

=head3 Args

=over 4

=item * C<$name> - optional test name.

=back

=head3 Returns

The test result.

=head3 Side Effects

Reports a test through L<Test::Builder>.  On failure, lists the captured
messages as diagnostics.

=head3 EXAMPLE

    $logger->empty('nothing was logged');

=head3 API SPECIFICATION

=head4 Input

    { name => { type => 'string', optional => 1 } }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    N messages were captured:       (diagnostic) the test       Look at the listed messages
                                    failed

=head3 FORMAL SPECIFICATION

    Empty
      ΞLogger
      result! : BOOL
      ─────────
      result! = true ⇔ log = ⟨⟩

=cut

sub empty {
	my ($self, $name) = @_;

	my $messages = $self->_object('empty')->{'messages'};

	return $self->_assert(!@{$messages}, $name, 'captured', $messages);
}

# _matching - captured entries whose message matches a pattern
#
# Purpose:      Shared by like() and unlike().
# Entry:        $self    - this logger.
#               $pattern - qr// or string.
# Exit:         Returns an array reference of matching entries, in order.
# Side effects: None.
sub _matching {
	my ($self, $pattern) = @_;

	return [ grep { $_->{'message'} =~ $pattern } @{$self->{'messages'}} ];
}

# _at_level - captured entries at one level
#
# Purpose:      Shared by count() and has_level().
# Entry:        $self  - this logger.
#               $level - level name, any case.
# Exit:         Returns an array reference of entries at that level.
# Side effects: None.
sub _at_level {
	my ($self, $level) = @_;

	my $wanted = lc($level);

	return [ grep { $_->{'level'} eq $wanted } @{$self->{'messages'}} ];
}

# _assert - report an assertion as a TAP test
#
# Purpose:      Shared by every assertion, so they report identically.
# Entry:        $self    - this logger.
#               $ok      - truth of the assertion.
#               $name    - test name, or undef.
#               $key     - i18n key heading the failure diagnostic.
#               $entries - array reference of entries to list on failure.
# Exit:         Returns Test::Builder's result.
# Side effects: Emits one TAP test; on failure, diagnostics.  The failure is
#               reported at the line that called the public assertion.
sub _assert {
	my ($self, $ok, $name, $key, $entries) = @_;

	# Skip this frame and the public assertion's
	local $Test::Builder::Level = $Test::Builder::Level + 2;
	my $result = Test::Builder->new()->ok($ok, $name);
	$self->_explain($key, $entries) if(!$ok);

	return $result;
}

# _explain - list the entries that explain a failed assertion
#
# Purpose:      Make a failure self-explanatory in the TAP output.
# Entry:        $self    - this logger.
#               $key     - i18n key for the heading ('captured' or 'matched').
#               $entries - array reference of entries.
# Exit:         Returns $self.
# Side effects: Prints at most $MAX_EXPLAIN entries plus a summary line.
sub _explain {
	my ($self, $key, $entries) = @_;

	my $total = scalar(@{$entries});
	$self->_emit($self->i18n($key, { count => $total }));

	my $last = ($total > $MAX_EXPLAIN) ? $MAX_EXPLAIN : $total;
	foreach my $entry (@{$entries}[0 .. $last - 1]) {
		$self->_emit($self->i18n('entry', { level => $entry->{'level'}, message => $entry->{'message'} }));
	}
	$self->_emit($self->i18n('truncated', { count => $total - $last })) if($total > $last);

	return $self;
}

=head2 verbose

Get or set verbose mode.

=head3 Purpose

Print every message, whatever the C<diag> rule, while debugging a test.

=head3 Args

=over 4

=item * C<$value> - optional; true to turn verbose mode on.

=back

=head3 Returns

The current setting, 1 or 0, after any change.

=head3 Side Effects

Changes the setting when given an argument.

=head3 EXAMPLE

    $logger->verbose(1);
    my $verbose = $logger->verbose();

=head3 API SPECIFICATION

=head4 Input

    { value => { type => 'scalar', optional => 1 } }

=head4 Output

    { type => 'integer', min => 0, max => 1 }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    verbose() must be called on an  called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Verbose
      ΔLogger
      value? : BOOL
      result! : BOOL
      ─────────
      verbose' = value?
      result! = verbose'
      log' = log ∧ threshold' = threshold ∧ lang' = lang

=cut

sub verbose {
	my ($self, @value) = @_;

	$self->_object('verbose');
	$self->{'verbose'} = ($value[0] ? 1 : 0) if(@value);

	return $self->{'verbose'};
}

=head2 level

Get or set the level threshold.

=head3 Purpose

Mirror L<Log::Abstraction/level>, for code under test that reads or
changes it.  The threshold only affects the C<is_E<lt>levelE<gt>()>
predicates: every message is still captured.

=head3 Args

=over 4

=item * C<$name> - optional level name, case-insensitive.

=back

=head3 Returns

Without an argument, the numeric threshold (0 to 7).  With a valid name, the
logger, for chaining.  With an invalid name, C<undef>, as
L<Log::Abstraction> does.

=head3 Side Effects

Changes the threshold; carps on an invalid name.

=head3 EXAMPLE

    $logger->level('error');
    print $logger->level();    # 3

=head3 API SPECIFICATION

=head4 Input

    { name => { type => 'string', optional => 1 } }

=head4 Output

    { type => ['integer', 'object'], optional => 1 }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    invalid syslog level 'X'        X is not a level name       Use a name from the level list
                                    (warning)

=head3 FORMAL SPECIFICATION

    SetLevel
      ΔLogger
      name? : NAME
      ─────────
      name? ∈ dom severity ⇒ threshold' = severity name?
      name? ∉ dom severity ⇒ threshold' = threshold
      log' = log

=cut

sub level {
	my ($self, $name) = @_;

	my $result = $self->_object('level')->{'level'};
	if(defined($name)) {
		my $severity = exists($SEVERITY{lc($name)}) ? $SEVERITY{lc($name)} : undef;
		$self->{'level'} = $severity if(defined($severity));
		carp($self->i18n('invalid_level', { level => $name })) if(!defined($severity));
		$result = defined($severity) ? $self : undef;
	}

	return $result;
}

=head2 flush

Does nothing.

=head3 Purpose

L<Log::Abstraction/flush> sends held e-mail digests; the double has none,
but code under test may call it.

=head3 Args

None.

=head3 Returns

The logger, for chaining.

=head3 Side Effects

None.

=head3 EXAMPLE

    $logger->flush();

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

None.

=head3 FORMAL SPECIFICATION

    Flush
      ΞLogger

=cut

sub flush {
	my $self = shift;

	return $self;
}

=head2 lang

Which language the logger's own messages are in.

=head3 Purpose

Let a test check the outcome of the C<lang> and C<country> options.

=head3 Args

None.

=head3 Returns

A language tag: C<en>, C<de>, C<fr>, C<zh>, or one supplied with the
C<i18n> option.

=head3 Side Effects

None.

=head3 EXAMPLE

    my $lang = Test::Log::Abstraction->new(country => 'FR')->lang();    # 'fr'

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'string', matches => qr/\A[a-z]{2,3}\z/ }

=head3 MESSAGES

    Message                         Meaning                     Resolution
    ------------------------------  --------------------------  -----------------------------
    lang() must be called on an     called on the class name    Call it on a logger object
    object, not on the class

=head3 FORMAL SPECIFICATION

    Lang
      ΞLogger
      result! : LANG
      ─────────
      result! = lang

=cut

sub lang {
	my $self = shift;

	return $self->_object('lang')->{'lang'};
}

=head1 PROTECTED METHODS

Callable from this class and its subclasses only (L<Sub::Protected>);
subclasses may override them.

=head2 _emit

    $self->_emit($text);

Sends one line to TAP diagnostics through L<Test::Builder>, so it works in
tests that never loaded L<Test::More>.  A string with characters above
C<0xFF> is UTF-8 encoded first, unless the output handle already has an
encoding layer, so that a translated message never warns
C<Wide character in print>.  Returns the logger.  Override it to send
captured messages somewhere else.

=cut

sub _emit :Protected {
	my ($self, $text) = @_;

	my $tb = Test::Builder->new();
	my $handle = $tb->in_todo() ? $tb->todo_output() : $tb->failure_output();
	my $layered = grep { /\A(?:utf8|encoding)/ } PerlIO::get_layers($handle);
	$text = Encode::encode('UTF-8', $text) if(!$layered && ($text =~ /[^\x00-\xFF]/));
	$tb->diag($text);

	return $self;
}

=head2 i18n

Render one of this module's messages in the logger's language.

=head3 Purpose

The single source of every user-facing string, so that messages can be
translated and overridden without touching the code.

=head3 Args

=over 4

=item * C<$key> - message key, such as C<needs_pattern>.

=item * C<\%args> - optional values for the template's placeholders.
C<class> defaults to the invocant's class.  C<count> selects a plural form
and C<gender> a gender form, when the template has them.

=back

A template is a string with C<%{name}s>-style placeholders, where any
C<sprintf> conversion (C<%{count}d>, C<%{ratio}.2f>) may follow the name,
and C<%%> is a literal C<%>.  A missing value is rendered as C<undef>,
without a warning.  Instead of a string, a template may be a hash reference
keyed by gender (C<male>, C<female>, ...) or by plural category (C<zero>,
C<one>, C<two>, C<few>, C<many>, C<other>); these nest, and C<other> is the
fallback.  C<zero> is used for a count of 0 when present, whatever the
language's rules.

The template is looked up in the C<i18n> option, then the built-in
catalogue, first for the logger's language and then for English; an unknown
key is returned as it is.

=head3 Returns

The message, as a character string.

=head3 Side Effects

None.

=head3 EXAMPLE

    my $text = $self->i18n('needs_pattern', { method => 'like' });
    # "Test::Log::Abstraction: like() needs a pattern"

    my $logger = Test::Log::Abstraction->new(i18n => {
        en => { greeting => { male => 'He logged %{count}d', female => 'She logged %{count}d' } },
    });

=head3 API SPECIFICATION

=head4 Input

    {
        key => { type => 'string' },
        args => { type => 'hashref', optional => 1 },
    }

=head4 Output

    { type => 'string' }

=head3 MESSAGES

None; it never fails.

=head3 FORMAL SPECIFICATION

    [KEY, TEMPLATE]
    catalogue : LANG ⇸ (KEY ⇸ TEMPLATE)

    I18n
      ΞLogger
      key? : KEY
      result! : TEXT
      ─────────
      key? ∈ dom (catalogue lang) ⇒ result! = render (catalogue lang key?)
      key? ∉ dom (catalogue lang) ∧ key? ∈ dom (catalogue en) ⇒
          result! = render (catalogue en key?)
      key? ∉ dom (catalogue lang) ∪ dom (catalogue en) ⇒ result! = key?

=head3 PSEUDOCODE

    language = the logger's, or the configured one for a class
    template = first of: i18n option[language][key], catalogue[language][key],
               i18n option[en][key], catalogue[en][key]
    if there is no template, return the key
    while the template is a hash: choose by gender, then by plural, then 'other'
    replace each %{name}conversion with sprintf(conversion, args[name])

=cut

sub i18n :Protected {
	my ($self, $key, $args) = @_;

	my $class = ref($self) || $self;
	my %args = (class => $class, %{$args || {}});
	my $lang = ref($self) ? $self->{'lang'} : _resolve_lang({});
	my $template = _template($self, $lang, $key);

	return defined($template) ? _interpolate(_variant($template, \%args, $lang), \%args) : $key;
}

# _template - find a message template
#
# Purpose:      Look a key up in the logger's overrides and the built-in
#               catalogue, in the requested language and then English.
# Entry:        $self - logger or class name.
#               $lang - language tag.
#               $key  - message key.
# Exit:         Returns the template (string or hash reference), or undef.
# Side effects: None.  exists() guards every level, as a Readonly hash
#               croaks if a lookup tries to autovivify into it.
sub _template {
	my ($self, $lang, $key) = @_;

	my $overrides = (ref($self) && $self->{'options'}->{'i18n'}) || {};

	# Overrides before built-ins, the logger's language before English
	my $found;
	SEARCH: foreach my $tag ($lang, $FALLBACK_LANG) {
		foreach my $source ($overrides, \%MESSAGES) {
			my $table = exists($source->{$tag}) ? $source->{$tag} : undef;
			next if((ref($table) ne 'HASH') || !exists($table->{$key}));
			$found = $table->{$key};
			last SEARCH;
		}
	}

	return $found;
}

# _variant - pick a gender or plural form of a template
#
# Purpose:      Resolve a hash-shaped template to a string.
# Entry:        $template - string or (nested) hash reference.
#               $args     - placeholder values; 'gender' and 'count' are
#               consulted.
#               $lang     - language, for its plural rules.
# Exit:         Returns a string; '' if no form applies.
# Side effects: None.  Each step descends one level, so it terminates.
sub _variant {
	my ($template, $args, $lang) = @_;

	while(ref($template) eq 'HASH') {
		my $gender = $args->{'gender'};
		my $form = (defined($gender) && exists($template->{$gender})) ? $gender : _plural($template, $args->{'count'}, $lang);
		$template = exists($template->{$form}) ? $template->{$form} : '';
	}

	return $template;
}

# _plural - choose a plural category for a count
#
# Purpose:      Apply the explicit 'zero' case, then the language's rule.
# Entry:        $template - hash reference of forms.
#               $count    - the count, or undef.
#               $lang     - language tag.
# Exit:         Returns the key to use: 'zero', a CLDR category present in
#               $template, or 'other'.
# Side effects: None.
sub _plural {
	my ($template, $count, $lang) = @_;

	# Without a numeric count there is nothing to pluralise on
	my $numeric = defined($count) && Scalar::Util::looks_like_number($count);
	my $rule = exists($PLURAL{$lang}) ? $PLURAL{$lang} : $PLURAL{$FALLBACK_LANG};
	my $form = !$numeric ? 'other' : (($count == 0) && exists($template->{'zero'})) ? 'zero' : $rule->($count);

	return exists($template->{$form}) ? $form : 'other';
}

# _interpolate - fill a template's %{name}s placeholders
#
# Purpose:      Named sprintf, so translators can reorder placeholders.
# Entry:        $template - string.
#               $args     - hash reference of values.
# Exit:         Returns the rendered string; a non-ASCII template yields a
#               character (UTF-8 flagged) string.
# Side effects: None.  Missing values become 'undef' without warning, and a
#               non-numeric value for a numeric conversion is rendered as
#               it is rather than as 0.
sub _interpolate {
	my ($template, $args) = @_;

	# Mark a translated template as characters, so _emit() can encode it
	utf8::upgrade($template) if($template =~ /[^\x00-\x7F]/);

	# Only data conversions are allowed: %n and vectors have no place in a
	# message, and an unknown conversion is left as literal text
	$template =~ s{%(?:(%)|\{(\w+)\}([-+ 0#]*\d{0,3}(?:\.\d{1,3})?[sdiufeEgGxXobc]))}{_format($1, $3, defined($2) ? $args->{$2} : undef)}ge;

	return $template;
}

# _format - render one placeholder of _interpolate()
#
# Purpose:      Keep the substitution free of nested matches, which would
#               reset $1..$3 in the middle of the replacement.
# Entry:        $percent    - '%' for a '%%' escape, else undef.
#               $conversion - sprintf conversion, such as 's' or '.2f'.
#               $value      - the value to render, or undef.
# Exit:         Returns the rendered text.
# Side effects: None; never warns.
sub _format {
	my ($percent, $conversion, $value) = @_;

	my $numeric = defined($value) && Scalar::Util::looks_like_number($value);
	my $text = defined($percent) ? '%'
		: !defined($value) ? 'undef'
		: ($numeric || ($conversion =~ /[sc]\z/)) ? sprintf("%$conversion", $value)
		: $value;

	return $text;
}

# _croak - throw a translated error from the caller's point of view
#
# Purpose:      The one way this module dies, so every fatal message is
#               translatable and reported at the caller's file and line.
# Entry:        $self - logger or class name.
#               $key  - message key.
#               $args - optional placeholder values.
# Exit:         Does not return.
# Side effects: Croaks.
sub _croak {
	my ($self, $key, $args) = @_;

	croak($self->i18n($key, $args));
}

=head1 LIMITATIONS

=over 4

=item * B<More lenient than the real thing.>  The syslog spellings
(C<warning>, C<err>, C<crit>, C<emerg>, C<panic>, C<informational>) are
methods here but not in L<Log::Abstraction> 0.39, so code that calls them
passes its tests and then dies in production.  They are kept for the
MyLogger code this module replaces; a C<strict> option that limits the
double to L<Log::Abstraction>'s real API would be safer.

=item * B<Aliases are recorded under the name called.>  C<count('warn')>
and C<has_level('warn')> do not see C<warning> calls, and C<fatal> is
recorded as C<fatal> where L<Log::Abstraction> records C<error>.  Tests
must assert on the spelling the code under test uses.

=item * B<C<level()> does not filter.>  The threshold only drives the
C<is_*> predicates; every message is captured whatever it is, which is
what a test usually wants but is not what L<Log::Abstraction> does.

=item * B<Rendering differs on purpose.>  C<undef> becomes C<undef>
rather than being dropped, and hash and array references are rendered as
data, so an exact-match assertion written against this double may not hold
against L<Log::Abstraction> output, and the reverse.

=item * B<Mixed encodings in diagnostics.>  A translated (non-English)
diagnostic that embeds a message logged as undecoded UTF-8 bytes is
printed double-encoded, because the bytes are taken to be Latin-1 when
joined to the character-string template.  English output is unaffected.

=item * B<Encapsulation is not enforced under a harness.>  L<Sub::Private>
and L<Sub::Protected> skip their checks when C<$ENV{HARNESS_ACTIVE}> is set,
which is always the case for a module that only runs inside tests.  The
checks apply under a plain C<perl t/foo.t>.  Turning the bypass off would
mean changing their process-wide configuration, which would break other
modules' white-box tests.

=item * B<Dependency weight.>  L<Params::Validate::Strict>,
L<Sub::Private>, L<Sub::Protected>, L<Readonly> and L<autodie> (with
L<IPC::System::Simple>) are runtime dependencies of what is otherwise a
small test helper.  L<Object::Configure> is deliberately not used:
it loads L<Log::Abstraction> itself, which a test double must not need.

=item * B<Home-grown i18n.>  L<Locale::Maketext> uses positional bracket
notation and has no gender support, and gettext-based modules need compiled
catalogues; neither fits a small, named-placeholder table.  The four
catalogues were written without review by native speakers.

=item * B<Single-process only.>  Messages are kept in memory in the
logger object; output logged in a child process is not seen by the parent.

=back

=head1 DIAGNOSTICS

See the C<MESSAGES> section of each method.  The messages can be translated
or overridden; see L</i18n>.

=head1 SEE ALSO

L<Log::Abstraction>, L<Test::Builder>, L<Test::Most>

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.

=cut

1;
