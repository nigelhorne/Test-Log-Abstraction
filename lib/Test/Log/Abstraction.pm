package Test::Log::Abstraction;

=head1 NAME

Test::Log::Abstraction - Capture log output in tests and assert on it

=head1 VERSION

0.002.0

=head1 SYNOPSIS

=head2 Check what your code logged

    use Test::Most;
    use Test::Log::Abstraction;

    # Give the test logger to the code that you are testing
    my $logger = Test::Log::Abstraction->new();
    my $obj = Some::Class->new(logger => $logger);

    $obj->do_something();

    # Each of these is one TAP test
    $logger->like(qr/updated/, 'do_something() logs that it updated');
    $logger->has_level('error', 'an error was logged');
    $logger->unlike(qr/fatal/, 'nothing fatal was logged');
    is($logger->count(), 3, 'three messages were logged');

    done_testing();

=head2 Check that nothing was logged

    my $logger = Test::Log::Abstraction->new();
    Some::Class->new(logger => $logger)->run();
    $logger->empty('a normal run logs nothing');

=head2 Test several steps with one logger

    my $logger = Test::Log::Abstraction->new();
    my $obj = Some::Class->new(logger => $logger);

    $obj->load('good.csv');
    $logger->empty('good file: no messages');

    $logger->clear();    # forget the messages from the first step
    $obj->load('bad.csv');
    $logger->has_level('warn', 'bad file: a warning');

=head2 Look at the messages yourself

    foreach my $entry (@{ $logger->messages() }) {
        print "$entry->{level}: $entry->{message}\n";
    }

    # Structured fields, from a call such as
    # $logger->info('user logged in', { user => 'alice' })
    is($logger->messages()->[0]->{fields}->{user}, 'alice', 'user field');

=head2 Control what is printed while the test runs

    # Print nothing (the messages are still captured)
    my $quiet = Test::Log::Abstraction->new(diag => 'none');

    # Print everything
    my $loud = Test::Log::Abstraction->new(verbose => 1);

    # Print only errors and more serious messages
    my $errors = Test::Log::Abstraction->new(diag => 'error');

=head2 Test code that checks the log level

    # The code under test does: if($logger->is_debug()) { ... }
    my $logger = Test::Log::Abstraction->new(level => 'warning');
    ok(!$logger->is_debug(), 'debug output is turned off');

=head2 Get this module's own messages in another language

    my $logger = Test::Log::Abstraction->new(lang => 'de');    # German
    my $french = Test::Log::Abstraction->new(country => 'FR');    # French

=head1 DESCRIPTION

=head2 What this module is

Some code writes log messages through a logger object.  In production that
object is usually a L<Log::Abstraction> logger.  In a test, you give the code
a C<Test::Log::Abstraction> object instead.

This object does not write the messages to a file.  It keeps them in a list
in memory.  After the code has run, your test can check the list: was a
message logged, at which level, and what did it say?

It never writes to disk, and it does not load any logging backend.

=head2 Which methods it has

=over 4

=item * B<Log levels.>  The level methods of L<Log::Abstraction>:
C<trace>, C<debug>, C<info>, C<notice>, C<warn>, C<error>, C<fatal>,
C<critical>, C<alert> and C<emergency>.  It also accepts the syslog names
C<warning>, C<err>, C<crit>, C<emerg>, C<panic> and C<informational>.

=item * B<Other logger methods.>  C<level()>, C<is_debug()> and the other
C<is_E<lt>levelE<gt>()> methods, C<messages()> and C<flush()>.  Code under
test may call these, so they work as they do in L<Log::Abstraction>.

=item * B<Test methods.>  C<like>, C<unlike>, C<has_level> and C<empty>.
Each one reports one test result, like C<ok()> in L<Test::More>.

=item * B<Helper methods.>  C<count>, C<clear>, C<verbose> and C<lang>.

=back

=head2 Which messages are printed

Every message is always stored.  This section is only about which messages
are also printed in the test output, as TAP comments (lines that start with
C<#>).

By default, C<warning> and more serious levels are printed.  So if a test
causes a warning by accident, you see it.  C<trace>, C<debug>, C<info> and
C<notice> messages are not printed.

Verbose mode prints every message.  Verbose mode is on when you pass
C<< verbose => 1 >> to C<new()>.  If you do not pass C<verbose>, it is on
when the environment variable C<TEST_VERBOSE> is true (C<prove -v> sets
it), or when C<VERBOSE> is true.

To choose the levels, use the C<diag> option of C<new()>:

=over 4

=item * C<'all'> - print every message.

=item * C<'none'> - print nothing (verbose mode still prints everything).

=item * A level name, such as C<'error'> - print that level and every more
serious level.

=item * A list, such as C<['info', 'error']> - print only these levels.

=back

When a test method fails, the messages that explain the failure are printed
under it.  So you can see why it failed without running the test again.

=head2 Levels and how serious they are

Each level has a number.  A lower number means a more serious message.
These are the syslog numbers.

    0  emergency, emerg, panic
    1  alert
    2  critical, crit, fatal
    3  error, err
    4  warning, warn
    5  notice
    6  info, informational
    7  debug, trace

=head2 Language of this module's messages

This module has its own messages: error messages, warnings, and the text
that explains a failed test.  They can be in English (C<en>), German
(C<de>), French (C<fr>) or Simplified Chinese (C<zh>).

The language is chosen like this.  The first rule that gives an answer is
used:

=over 4

=item 1. The C<lang> option, for example C<< lang => 'de' >>.

=item 2. The C<country> option, a two-letter country code such as C<'FR'>.

=item 3. Only when C<< lang => 'auto' >>: the environment variables
C<LC_ALL>, C<LC_MESSAGES> and C<LANG>, in that order.

=item 4. C<$Test::Log::Abstraction::config{lang}>, which is C<'en'>.

=back

The default is English, not the language of your computer.  This is on
purpose: the test output is then the same on every computer.

If a message has no translation, the English message is used.  You can add
or change messages with the C<i18n> option of C<new()>.

This only changes this module's own messages.  The messages that your code
logs are never changed.

=head2 Default settings

The defaults for C<new()> are in the hash
C<%Test::Log::Abstraction::config>.  It has the same keys as the options of
C<new()>.  You can change it in a test, or fill it with
L<Object::Configure>:

    $Test::Log::Abstraction::config{'diag'} = 'none';

A change only affects loggers that are created after it.

=head2 Moving from t/lib/MyLogger.pm

Many distributions have their own copy of a small test logger in
F<t/lib/MyLogger.pm>.  To use this module instead, change each test file
from:

    use lib 't/lib';
    use MyLogger;
    ...
    logger => MyLogger->new()

to:

    use Test::Log::Abstraction;
    ...
    logger => Test::Log::Abstraction->new()

Then delete F<t/lib/MyLogger.pm>.  This module is the same in every
distribution.  It does not loop forever when a level method is given
C<undef> (an old MyLogger bug; see F<t/autoload.t>).  And it keeps every
message, so your tests can check them.

=head1 COMMON PITFALLS

=over 4

=item * B<The test methods are tests.>  C<like>, C<unlike>, C<has_level>
and C<empty> each add one test to the TAP output.  If you give a test
plan (C<< tests => 5 >>), count them.  Or use C<done_testing()>.

=item * B<Messages from earlier steps are still there.>  A logger keeps
every message until you call C<clear()>.  If one logger is used for
several steps, C<like> may match a message from an earlier step.

=item * B<A string pattern is a regular expression.>  C<like('a.c')>
matches C<'abc'>, because C<.> means "any character".  To match the text
exactly, use C<qr/\Qa.c\E/>.

=item * B<Different names for one level are counted apart.>  C<warn> and
C<warning> have the same number, but C<count('warn')> and
C<has_level('warn')> do not see messages logged with C<warning()>.  Check
the name that the code under test uses.  C<fatal> is stored as C<fatal>,
but L<Log::Abstraction> stores it as C<error>.

=item * B<C<undef> is not the same as "no value".>

=over 4

=item * An C<undef> argument to a level method becomes the text
C<undef> in the message.  (L<Log::Abstraction> drops it.)

=item * C<< verbose => undef >> turns verbose mode B<off>.  To use the
environment variables instead, do not pass C<verbose> at all.

=item * C<< diag => undef >> and C<< level => undef >> use the default
from C<%config>.

=item * C<count(undef)> counts all messages.  C<level(undef)> returns the
level number and changes nothing.

=item * C<like(undef)>, C<unlike(undef)> and C<has_level(undef)> stop the
test with an error.

=back

=item * B<One hash reference, or a hash reference at the end.>
C<< $logger->info({ a => 1 }) >> logs the text C<{a =E<gt> 1}>.  But
C<< $logger->info('text', { a => 1 }) >> logs the text C<text> and stores
C<< { a => 1 } >> in C<fields>.  An empty hash at the end is dropped.

=item * B<Copies are shallow (only one level deep).>

=over 4

=item * When a message has C<fields>, the fields hash is copied.  But a
hash or array B<inside> the fields is not copied.  If your code changes it
later, the stored message changes too.

=item * C<messages()> returns a new list, but the entries in it are the
stored entries.  Do not change them, unless you want to change what was
captured.

=item * When you clone a logger with C<< $logger->new(%options) >>, each
option replaces the old option completely.  For example,
C<< $logger->new(i18n => { de => {...} }) >> replaces the whole C<i18n>
hash.  The translations in the old hash are not kept.

=back

=item * B<The C<i18n> option is merged message by message.>  You only
need to give the messages that you want to change.  For each message,
this module looks in your C<i18n> hash first, and then in its own list.
So any message that you do not give keeps its normal text.

=item * B<A misspelt method name does not stop the test.>
C<< $logger->wran('x') >> stores the message under the name C<wran> and
prints a notice.  The test still passes, unless you check the messages.

=item * B<C<prove -v> prints everything.>  C<prove -v> sets
C<TEST_VERBOSE>, which turns verbose mode on.  If a test checks what is
printed, set C<< verbose => 0 >> or C<$ENV{TEST_VERBOSE} = 0>.

=item * B<C<level()> does not hide messages.>  It only changes the answers
of the C<is_*> methods.  Every message is still stored.

=back

=head1 ENCODING

This module never changes the text that your code logs.  It stores each
message exactly as it was given.

=over 4

=item * B<Log messages and fields: any text.>  ASCII, other languages and
emoji are all stored safely.  It does not matter if the text is a Perl
character string (decoded, for example with C<use utf8> or
L<Encode/decode>) or a byte string (for example, UTF-8 bytes read from a
file).

=item * B<Matching with C<like> and C<unlike>.>  The pattern is matched
against the stored text as it is.  So the pattern and the message must be
the same kind of string.  A pattern with a character, such as
C<qr/\x{1F600}/>, does not match the same emoji stored as UTF-8 bytes.

=item * B<Printed messages.>  A Perl character string that has any
character above ASCII is printed as UTF-8.  A byte string is printed
unchanged.  Perl cannot always see the difference: a string that was not
decoded, and has no character above 255 (such as C<"caf\x{e9}">), is
treated as bytes.  If the output already has an encoding layer (for example, set
by L<Test2::Plugin::UTF8>), the text is not encoded again.

=item * B<This module's own messages.>  German, French and Chinese messages
are character strings, and they are printed as UTF-8.  There is one
problem case: a translated message that includes a logged message that is
a non-ASCII byte string.  That part of the text is printed wrongly (it is
encoded twice).  English messages do not have this problem.

=item * B<Options.>  C<lang> and C<country> must be ASCII, in the formats
given under L</new>.  Level names are ASCII.  Templates in the C<i18n>
option may contain any characters, but placeholder names must be ASCII
letters, digits or C<_>.

=item * B<Test names.>  Test names are passed to L<Test::Builder>
unchanged.

=back

=cut

use 5.014;
use strict;
use warnings;
use autodie qw(:all);

use Carp qw(carp croak);
use Encode ();
use overload ();
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
		_entry _explain _format _interpolate _matching _object _plural _reason
		_record _resolve_lang _template _validate _variant
	));
}

# _stringify is deliberately not in that list.  It recurses, and Sub::Private
# re-enters a wrapped sub with goto from inside its own file, where
# 'recursion' warnings are on, so logging a structure more than 100 levels
# deep would warn however this file sets its warnings.

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
	fr => sub { (abs($_[0]) < 2) ? 'one' : 'other' },	# French counts 0 as singular
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

# Schema for count()
Readonly::Hash my %COUNT_SCHEMA => (
	level => { type => 'string', optional => 1 },
);

# Schema for has_level()
Readonly::Hash my %LEVEL_SCHEMA => (
	level => { type => 'string' },
	name => { type => 'string', optional => 1 },
);

=head1 METHODS

=head2 new

Create a new test logger.

=head3 Purpose

Make a logger that stores every message it is given, so that your test can
check the messages later.

=head3 Args

All options are optional.  Give them as a list (C<< key => value >>) or as
one hash reference.

=over 4

=item * C<verbose> - true: print every message.  False: use the C<diag>
rule.  If you do not give it, the value of C<$ENV{TEST_VERBOSE}> or
C<$ENV{VERBOSE}> is used.

=item * C<diag> - which messages to print.  C<'all'>, C<'none'>, a level
name (print that level and every more serious level), or an array
reference of level names.  Upper or lower case does not matter.  The
default is C<'warning'>.

=item * C<level> - the level that C<level()> and the C<is_*> methods
report.  The default is C<'trace'>, so every C<is_*> method returns 1, and
the code under test runs all its debug code.  This option does not stop
any message from being stored.

=item * C<lang> - the language of this module's own messages: C<'en'>,
C<'de'>, C<'fr'>, C<'zh'>, a locale name such as C<'de_DE.UTF-8'>, or
C<'auto'> (read the environment).  Must be 2 or 3 ASCII letters, then
optionally C<_>, C<.>, C<@> or C<-> and more text.

=item * C<country> - a two-letter country code such as C<'GB'> or
C<'fr'> (upper or lower case).  Used to choose the language when C<lang>
is not given.

=item * C<i18n> - your own message texts, as
C<< { language => { message_key => template } } >>.  See L</i18n>.

=back

Other options are allowed and ignored.  (A L<Log::Abstraction>
configuration hash can be passed unchanged.)  If you pass an odd number of
arguments, they are all ignored.  This is for the old MyLogger code, which
sometimes passed one stray argument.

=head3 Three ways to call it

=over 4

=item * C<< Test::Log::Abstraction->new(%options) >> - the usual way.

=item * C<< $logger->new(%options) >> - make a B<clone>: a new logger with
the same options, the same C<verbose> and C<level> settings, and a copy of
the stored messages.  The options that you pass replace the old ones.

=item * C<Test::Log::Abstraction::new(%options)> - called as a function.
This works too.

=back

=head3 Returns

The new logger object.

=head3 Side Effects

Reads C<%ENV> to decide on verbose mode, and, with C<< lang => 'auto' >>,
to choose the language.  Nothing else changes.  A clone does not change the
original logger.

=head3 EXAMPLE

    # The usual way
    my $logger = Test::Log::Abstraction->new();

    # Store everything, print nothing
    my $quiet = Test::Log::Abstraction->new(diag => 'none');

    # A hash reference works too; messages in German
    my $german = Test::Log::Abstraction->new({ country => 'DE' });

    # A clone that prints everything; $logger is not changed
    my $loud = $logger->new(diag => 'all');

=head3 API SPECIFICATION

=head4 Input

    {
        verbose => { type => 'scalar', optional => 1 },
        diag => { type => ['string', 'arrayref'], optional => 1 },
        level => { type => 'string', optional => 1 },
        lang => { type => 'string', optional => 1, matches => qr/\A(?:auto|[A-Za-z]{2,3}(?:[_.\@-][\w.\@-]*)?)\z/ },
        country => { type => 'string', optional => 1, matches => qr/\A[A-Za-z]{2}\z/ },
        i18n => { type => 'hashref', optional => 1 },
    }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

All of these stop the program (C<croak>).

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    invalid diag level 'X'          X is not a level name         Use a name from the level table
    diag must be a level name ...   diag is a hash or code ref    Give a string or an array ref
    invalid syslog level 'X'        the level option is unknown   Use a name from the level table
    invalid argument: ...           an option has the wrong type  Fix the option that is named
                                    or format

=head3 PSEUDOCODE

    if new() was called on a logger object:
        options = the object's options, replaced by the new options
        build a logger from the options, with a copy of the messages
        copy verbose and level from the object, unless new values were given
    else:
        if new() was called as a function, the first argument is an option
        turn the arguments into a hash (ignore an odd-length list)
        check the options
        choose the language, then the diag rule, then the level
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
	# test run, so only hand it
	# shapes that it accepts; an undefined key would also make it warn
	my $keys_defined = !grep { !defined($args->[$_]) } grep { !($_ % 2) } 0 .. $#{$args};
	my $usable = ((@{$args} == 1) && (ref($args->[0]) eq 'HASH')) || (@{$args} && !(@{$args} % 2) && $keys_defined);
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
	my $level = defined($valid->{'level'}) ? $valid->{'level'} : $config{'level'};
	$level = defined($level) ? lc($level) : 'undef';
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

	my $copy = [ map { +{ %{$_}, ($_->{'fields'} ? (fields => { %{$_->{'fields'}} }) : ()) } } @{$self->{'messages'}} ];
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
		$self->_croak('invalid_argument', { reason => _reason($reason) });
	}

	return $valid || {};
}

# _reason - strip the location from an error message
#
# Purpose:      An error raised inside another module names that module's
#               file and line; the caller only needs the explanation.
# Entry:        $error - error text, such as $@.
# Exit:         Returns the text without a trailing ' at FILE line N.'.
# Side effects: None.
sub _reason {
	my $error = shift;

	(my $reason = defined($error) ? "$error" : '') =~ s/\s+at \S+ line \d+\.?\s*\z//s;

	return $reason;
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
	} elsif(defined($wanted) && (lc($wanted) eq $LANG_AUTO)) {
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
	$self->_croak('invalid_diag_level', { level => 'undef' }) if(!defined($spec));

	# 'all' and 'none' are matched without regard to case, as level names are
	my $name = lc($spec);
	return {} if($name eq $DIAG_NONE);
	return { all => 1 } if($name eq $DIAG_ALL);
	$self->_croak('invalid_diag_level', { level => $spec }) if(!exists($SEVERITY{$name}));

	return { threshold => $SEVERITY{$name} };
}

=head2 trace, debug, info, notice, warn, error, fatal, critical, alert, emergency

Store a message at this level.

=head3 Purpose

These are the methods that the code under test calls to log something.
There is one method for each L<Log::Abstraction> level, and one for each
syslog name: C<warning>, C<err>, C<crit>, C<emerg>, C<panic> and
C<informational>.  Each method stores the message under the name that was
called, and may print it (see L</Which messages are printed>).

By default:

=over 4

=item * C<trace>, C<debug>, C<info>, C<informational>, C<notice> - stored,
not printed.

=item * C<warn>, C<warning>, C<error>, C<err>, C<critical>, C<crit>,
C<fatal>, C<alert>, C<emergency>, C<emerg>, C<panic> - stored and printed.

=back

=head3 Args

Any list of values.  They are turned into one message like this:

=over 4

=item * All the values are joined together, with nothing between them.

=item * One newline at the end is removed.

=item * If the only value is an array reference, its items are the parts
of the message.

=item * If there are two or more values and the last one is a hash
reference, that hash is not part of the message.  A copy of it is stored as
C<fields>.  An empty hash is dropped.

=item * A hash reference in the message is written as
C<{key =E<gt> value, ...}>, with the keys sorted.  An array reference is
written as C<[a, b]>.  So you can match their contents.

=item * C<undef> is written as the text C<undef>.  There is no warning.

=item * An object is written as Perl normally writes it.  If the object
has its own text form (overloaded C<"">), that form is used.

=item * A structure that contains itself is written as C<(cycle)> at the
point where it repeats.

=back

=head3 Returns

The logger, as in L<Log::Abstraction>.  So you can chain calls:
C<< $logger->info('a')->info('b') >>.

=head3 Side Effects

Adds one entry to the stored messages.  May print the message.  The
variables C<$@> and C<$!> are not changed.  So you can log inside an error
handler without losing the error.

=head3 EXAMPLE

    $logger->warn('something looks wrong');
    $logger->warn('file ', $name, ' is empty');          # joined: one message
    $logger->info('started', { pid => $$ });             # message + fields
    $logger->error({ error => 'cannot open file' });     # hash as the message
    $logger->debug(['part 1, ', 'part 2']);              # array of parts

=head3 API SPECIFICATION

=head4 Input

    {
        messages => { type => 'arrayref', position => 0, slurp => 1 },
    }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    X() must be called on an        not called on a logger,       Call it on a logger object
    object, not on the class        not on a logger (croak)

=cut

# Generate the level methods.  Each is a thin wrapper over _record, and they
# exist as real methods so that AUTOLOAD only sees genuinely unknown names
foreach my $level (keys %SEVERITY) {
	no strict 'refs';	## no critic (ProhibitNoStrict)
	*{$level} = sub {
		my $self = shift;
		return _object($self, $level)->_record($level, \@_);
	};
}

=head2 is_trace, is_debug, is_info, is_notice, is_warn, is_error, is_critical, is_alert, is_emergency

Ask if a level is turned on.

=head3 Purpose

Some code only builds a log message if the level is turned on, for
example C<< if($logger->is_debug()) { ... } >>.  These methods answer that
question, as L<Log::Abstraction> does.

=head3 Args

None.

=head3 Returns

1 if the level is turned on, otherwise 0.  A level is turned on when its
number is the same as, or lower than, the logger's level (see L</level>).
The default level is C<trace>, so all these methods return 1.

=head3 Side Effects

None.

=head3 EXAMPLE

    $logger->level('warning');
    $logger->is_warn();     # 1
    $logger->is_error();    # 1 (more serious than warning)
    $logger->is_info();     # 0 (less serious than warning)

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    is_X() must be called on an     not called on a logger        Call it on a logger object
    object, not on the class        (croak)

=cut

foreach my $level (@PREDICATES) {
	my $method = "is_$level";
	no strict 'refs';	## no critic (ProhibitNoStrict)
	*{$method} = sub {
		my $self = shift;
		return (_object($self, $method)->{'level'} >= $SEVERITY{$level}) ? 1 : 0;
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
# Side effects: Croaks with 'class_invocant' unless $self is an object of
#               this class or a subclass.
sub _object {
	my ($self, $method) = @_;

	# Called as a function, because the invocant may be undef, an unblessed
	# reference or another class's object, none of which can call methods
	my $ok = Scalar::Util::blessed($self) && $self->isa(__PACKAGE__);
	my $class = (defined($self) && !ref($self) && UNIVERSAL::isa($self, __PACKAGE__)) ? $self : __PACKAGE__;
	_croak($class, 'class_invocant', { method => $method }) if(!$ok);

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
#               caller cannot rewrite the captured history.  Never dies, and
#               leaves $@ alone.
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

	# A part that cannot be rendered at all (a tied hash whose FETCH dies,
	# say) is shown in Perl's plain form, so that logging never dies
	local $@;
	my $message = join('', map { my $part = $_; my $text = eval { _stringify($part, {}) }; defined($text) ? $text : overload::StrVal($part) } @args);

	# Not chomp(): that obeys $/, which the code under test may have changed
	$message =~ s/\n\z//;
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
# Side effects: None.  $seen is restored on return.  Never dies or warns:
#               an object whose overloaded "" dies is shown as Class=HASH(...).
sub _stringify {
	my ($value, $seen) = @_;

	# Deeply nested data is legitimate; Perl's warning at depth 100 is noise
	no warnings 'recursion';	## no critic (ProhibitNoWarnings)

	return 'undef' if(!defined($value));

	# Plain scalars, objects and other reference types: Perl's own form.  An
	# object's overloaded "" may die or return undef; neither may break a
	# log call, so fall back to the form that ignores overloading
	my $type = ref($value);
	if(($type ne 'HASH') && ($type ne 'ARRAY')) {
		local $@;	# the caught error must not reach the caller
		my $text = eval { no warnings 'uninitialized'; my $string = "$value"; $string };	## no critic (ProhibitNoWarnings)
		return defined($text) ? $text : overload::StrVal($value);
	}

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

Handle a call to a method that does not exist.

=head3 Purpose

Perl calls this when the code under test calls a method that this class
does not have - usually a misspelt level, such as C<wran>.  Instead of
stopping the test, the message is stored under the name that was called,
and a notice is printed.  The notice is always printed, whatever the
C<diag> setting, so the mistake is not hidden.

=head3 Args

The same as a level method.

=head3 Returns

The logger.

=head3 Side Effects

Adds one entry, with the called name as its level.  Prints
C<no method 'name'>.

=head3 EXAMPLE

    $logger->wran('oops');    # stored at level 'wran'; a notice is printed
    is($logger->count('wran'), 1, 'the misspelt call was stored');

=head3 API SPECIFICATION

=head4 Input

    {
        messages => { type => 'arrayref', position => 0, slurp => 1 },
    }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    no method 'X'                   X is not a method or a level  Fix the method name
                                    (notice; the test goes on)
    X() must be called on an        an unknown method was called  Call it on a logger object
    object, not on the class        on the class name (croak)

=cut

sub AUTOLOAD {
	my ($self, @args) = @_;

	my ($name) = ($AUTOLOAD =~ /::([^:]+)\z/);
	_object($self, $name)->_record($name, \@args);

	return $self->_emit($self->i18n('no_method', { method => $name }));
}

# Defined so that object destruction never reaches AUTOLOAD
sub DESTROY { }

=head2 messages

Get the stored messages.

=head3 Purpose

Let your test look at everything that was logged.

=head3 Args

None.

=head3 Returns

A reference to a new array.  It has one hash reference for each message,
oldest first.  Each hash has these keys:

=over 4

=item * C<level> - the level name, in lower case, as it was called.

=item * C<message> - the message text.

=item * C<fields> - only when fields were given: a hash reference.

=back

The array is a copy, as in L<Log::Abstraction>.  Adding or removing items
in it does not change the stored messages.  But the hashes in it are the
stored hashes (see L</COMMON PITFALLS>).

=head3 Side Effects

None.

=head3 EXAMPLE

    foreach my $entry (@{ $logger->messages() }) {
        diag("$entry->{level}: $entry->{message}");
    }

    my $first = $logger->messages()->[0];
    is($first->{level}, 'warn', 'the first message is a warning');

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'arrayref' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    messages() must be called on    not called on a logger        Call it on a logger object
    an object, not on the class     (croak)

=cut

sub messages {
	my $self = shift;

	return [ @{_object($self, 'messages')->{'messages'}} ];
}

=head2 clear

Delete all stored messages.

=head3 Purpose

Start again with an empty list, for example between two steps of a test.

=head3 Args

None.

=head3 Returns

The logger, so you can chain calls.

=head3 Side Effects

All stored messages are deleted.  The settings (C<verbose>, C<level>,
C<diag>, language) do not change.

=head3 EXAMPLE

    $logger->clear();
    $logger->clear()->empty('nothing logged yet');

=head3 API SPECIFICATION

=head4 Input

    {}

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    clear() must be called on an    not called on a logger        Call it on a logger object
    object, not on the class        (croak)

=cut

sub clear {
	my $self = shift;

	@{_object($self, 'clear')->{'messages'}} = ();

	return $self;
}

=head2 count

Count the stored messages.

=head3 Purpose

Check how much was logged, in total or at one level.

=head3 Args

=over 4

=item * C<$level> - optional.  Count only messages at this level.  Upper or
lower case does not matter.  Different names for the same level are counted
apart: C<count('warn')> does not count C<warning()> calls.

=back

=head3 Returns

The number of messages: 0 or more.

=head3 Side Effects

None.

=head3 EXAMPLE

    is($logger->count(), 3, 'three messages in total');
    is($logger->count('error'), 1, 'one of them is an error');

=head3 API SPECIFICATION

=head4 Input

    {
        level => { type => 'string', optional => 1, position => 0 },
    }

=head4 Output

    { type => 'integer', min => 0 }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    count() must be called on an    not called on a logger        Call it on a logger object
    object, not on the class        (croak)
    invalid argument: ...           the level is not a string     Give a level name
                                    (croak)

=cut

sub count {
	my ($self, $level) = @_;

	my $messages = _object($self, 'count')->{'messages'};
	$self->_validate(\%COUNT_SCHEMA, { level => $level }) if(defined($level));

	return defined($level) ? scalar(@{$self->_at_level($level)}) : scalar(@{$messages});
}

=head2 like

Test that a stored message matches a pattern.

=head3 Purpose

The test passes if at least one stored message matches the pattern.

=head3 Args

=over 4

=item * C<$pattern> - required.  A C<qr//> regular expression, or a string.
A string is also used as a regular expression.

=item * C<$name> - optional.  The name of the test.

=back

=head3 Returns

True if the test passed, false if it failed.

=head3 Side Effects

Adds one test result to the TAP output.  If the test fails, all stored
messages are printed under it (at most 20, then a count of the others).

=head3 EXAMPLE

    $logger->like(qr/updated/, 'the update was logged');
    $logger->like(qr/^Cannot open/i, 'the open error was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        pattern => { type => ['regex', 'string'], position => 0 },
        name => { type => 'string', optional => 1, position => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    like() needs a pattern          no pattern was given (croak)  Give a qr// or a string
    invalid argument: ...           the pattern is not a qr// or  Give a qr// or a string
                                    a string, does not compile,   that is a valid regex
                                    or can never match (croak)
    N messages were captured:       the test failed; the stored   Compare them with the pattern
                                    messages follow (output)

=cut

sub like {
	my ($self, $pattern, $name) = @_;

	_object($self, 'like');
	$self->_croak('needs_pattern', { method => 'like' }) if(!defined($pattern));
	my $valid = $self->_validate(\%PATTERN_SCHEMA, { pattern => $pattern, (defined($name) ? (name => $name) : ()) });

	return $self->_assert(scalar(@{$self->_matching($valid->{'pattern'})}), $name, 'captured', $self->{'messages'});
}

=head2 unlike

Test that no stored message matches a pattern.

=head3 Purpose

The test passes if no stored message matches the pattern.  It also passes
when there are no messages.

=head3 Args

=over 4

=item * C<$pattern> - required.  A C<qr//> regular expression, or a string.
A string is also used as a regular expression.

=item * C<$name> - optional.  The name of the test.

=back

=head3 Returns

True if the test passed, false if it failed.

=head3 Side Effects

Adds one test result to the TAP output.  If the test fails, the messages
that matched are printed under it.

=head3 EXAMPLE

    $logger->unlike(qr/fatal/i, 'nothing fatal was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        pattern => { type => ['regex', 'string'], position => 0 },
        name => { type => 'string', optional => 1, position => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    unlike() needs a pattern        no pattern was given (croak)  Give a qr// or a string
    invalid argument: ...           the pattern is not a qr// or  Give a qr// or a string
                                    a string, does not compile,   that is a valid regex
                                    or can never match (croak)
    N messages matched:             the test failed; the          Look at the listed messages
                                    matching messages follow

=cut

sub unlike {
	my ($self, $pattern, $name) = @_;

	_object($self, 'unlike');
	$self->_croak('needs_pattern', { method => 'unlike' }) if(!defined($pattern));
	my $valid = $self->_validate(\%PATTERN_SCHEMA, { pattern => $pattern, (defined($name) ? (name => $name) : ()) });
	my $matches = $self->_matching($valid->{'pattern'});

	return $self->_assert(!@{$matches}, $name, 'matched', $matches);
}

=head2 has_level

Test that something was logged at a level.

=head3 Purpose

The test passes if at least one message was stored at this level.

=head3 Args

=over 4

=item * C<$level> - required.  The level name.  Upper or lower case does
not matter.  Different names for the same level are different:
C<has_level('warn')> does not see C<warning()> calls.

=item * C<$name> - optional.  The name of the test.

=back

=head3 Returns

True if the test passed, false if it failed.

=head3 Side Effects

Adds one test result to the TAP output.  If the test fails, all stored
messages are printed under it, so you can see which levels were used.

=head3 EXAMPLE

    $logger->has_level('error', 'the failure was logged');

=head3 API SPECIFICATION

=head4 Input

    {
        level => { type => 'string', position => 0 },
        name => { type => 'string', optional => 1, position => 1 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    has_level() needs a level name  no level was given (croak)    Give a level name
    invalid argument: ...           the level is not a string     Give a level name
                                    (croak)
    N messages were captured:       the test failed; the stored   Look at the listed levels
                                    messages follow (output)

=cut

sub has_level {
	my ($self, $level, $name) = @_;

	_object($self, 'has_level');
	$self->_croak('needs_level', { method => 'has_level' }) if(!defined($level));
	my $valid = $self->_validate(\%LEVEL_SCHEMA, { level => $level, (defined($name) ? (name => $name) : ()) });

	return $self->_assert(scalar(@{$self->_at_level($valid->{'level'})}), $name, 'captured', $self->{'messages'});
}

=head2 empty

Test that nothing was logged.

=head3 Purpose

The test passes if there are no stored messages.  Use it to check that a
normal run logs nothing.

=head3 Args

=over 4

=item * C<$name> - optional.  The name of the test.

=back

=head3 Returns

True if the test passed, false if it failed.

=head3 Side Effects

Adds one test result to the TAP output.  If the test fails, the stored
messages are printed under it.

=head3 EXAMPLE

    $logger->empty('a normal run logs nothing');

=head3 API SPECIFICATION

=head4 Input

    {
        name => { type => 'string', optional => 1, position => 0 },
    }

=head4 Output

    { type => 'boolean' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    N messages were captured:       the test failed; the stored   Look at the listed messages
                                    messages follow (output)

=cut

sub empty {
	my ($self, $name) = @_;

	my $messages = _object($self, 'empty')->{'messages'};

	return $self->_assert(!@{$messages}, $name, 'captured', $messages);
}

# _matching - captured entries whose message matches a pattern
#
# Purpose:      Shared by like() and unlike().
# Entry:        $self    - this logger.
#               $pattern - qr// or string.
# Exit:         Returns an array reference of matching entries, in order.
# Side effects: Croaks with 'invalid_argument' if the pattern does not
#               compile.
sub _matching {
	my ($self, $pattern) = @_;

	# A string is compiled here, so that a malformed one, one with code in
	# it (not allowed at run time), or one Perl warns can never match, is
	# the caller's error and not a crash or a stray warning
	my $regex = eval { use warnings FATAL => 'regexp'; qr/$pattern/ };
	$self->_croak('invalid_argument', { reason => _reason($@) }) if(!defined($regex));

	return [ grep { $_->{'message'} =~ $regex } @{$self->{'messages'}} ];
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

Get or change verbose mode.

=head3 Purpose

In verbose mode, every message is printed, whatever the C<diag> rule says.
This helps when you are finding out why a test fails.

=head3 Args

=over 4

=item * C<$value> - optional.  True turns verbose mode on, false turns it
off.  Without an argument, nothing changes.

=back

=head3 Returns

The setting after the call: 1 (on) or 0 (off).

=head3 Side Effects

Changes the setting, when you give an argument.

=head3 EXAMPLE

    $logger->verbose(1);           # print everything from now on
    my $on = $logger->verbose();   # 1

=head3 API SPECIFICATION

=head4 Input

    {
        value => { type => 'scalar', optional => 1, position => 0 },
    }

=head4 Output

    { type => 'integer', min => 0, max => 1 }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    verbose() must be called on an  not called on a logger        Call it on a logger object
    object, not on the class        (croak)

=cut

sub verbose {
	my ($self, @value) = @_;

	_object($self, 'verbose');
	$self->{'verbose'} = ($value[0] ? 1 : 0) if(@value);

	return $self->{'verbose'};
}

=head2 level

Get or change the logger's level.

=head3 Purpose

Code under test may read or change the level, as it can with
L<Log::Abstraction/level>.  The level only changes the answers of the
C<is_*> methods.  Every message is still stored.

=head3 Args

=over 4

=item * C<$name> - optional.  A level name.  Upper or lower case does not
matter.

=back

=head3 Returns

=over 4

=item * No argument: the level's number, from 0 to 7.

=item * A known level name: the logger, so you can chain calls.

=item * An unknown level name: C<undef>, as in L<Log::Abstraction>.

=back

=head3 Side Effects

With a known name, the level changes.  With an unknown name, nothing
changes and a warning is printed.

=head3 EXAMPLE

    $logger->level('error');
    print $logger->level(), "\n";    # 3

=head3 API SPECIFICATION

=head4 Input

    {
        name => { type => 'string', optional => 1, position => 0 },
    }

=head4 Output

    { type => ['integer', 'object'], optional => 1 }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    invalid syslog level 'X'        X is not a level name         Use a name from the level table
                                    (warning; returns undef)

=cut

sub level {
	my ($self, $name) = @_;

	my $result = _object($self, 'level')->{'level'};
	if(defined($name)) {
		my $severity = exists($SEVERITY{lc($name)}) ? $SEVERITY{lc($name)} : undef;
		$self->{'level'} = $severity if(defined($severity));
		carp($self->i18n('invalid_level', { level => $name })) if(!defined($severity));
		$result = defined($severity) ? $self : undef;
	}

	return $result;
}

=head2 flush

Do nothing.

=head3 Purpose

In L<Log::Abstraction>, C<flush()> sends e-mail messages that are waiting.
The test logger never sends e-mail, but the code under test may still call
C<flush()>, so it exists.

=head3 Args

None.

=head3 Returns

The logger, so you can chain calls.

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

=cut

sub flush {
	my $self = shift;

	return $self;
}

=head2 lang

Get the language of this module's messages.

=head3 Purpose

Let a test check which language was chosen from the C<lang> and C<country>
options or the environment.

=head3 Args

None.

=head3 Returns

A language code: C<en>, C<de>, C<fr>, C<zh>, or a code that you gave in the
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

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    lang() must be called on an     not called on a logger        Call it on a logger object
    object, not on the class        (croak)

=cut

sub lang {
	my $self = shift;

	return _object($self, 'lang')->{'lang'};
}

=head1 PROTECTED METHODS

Only this class, and classes that inherit from it, may call these methods
(L<Sub::Protected> checks this).  A subclass may replace them.

=head2 _emit

Print one line of test output.

=head3 Purpose

Every line that this module prints goes through this method.  A subclass
can replace it to send the lines somewhere else.

=head3 Args

=over 4

=item * C<$text> - the line to print.

=back

=head3 Returns

The logger.

=head3 Side Effects

Prints the line as a TAP comment, with L<Test::Builder/diag>.  This works
even if the test did not load L<Test::More>.  A Perl character string is
encoded as UTF-8 first, unless the output already has an encoding layer
(see L</ENCODING>).

=head3 EXAMPLE

    package My::Logger;
    use parent -norequire, 'Test::Log::Abstraction';

    # Send the lines to STDERR instead of the TAP output
    sub _emit {
        my ($self, $text) = @_;
        print STDERR "$text\n";
        return $self;
    }

=head3 API SPECIFICATION

=head4 Input

    {
        text => { type => 'string', position => 0 },
    }

=head4 Output

    { type => 'object', isa => 'Test::Log::Abstraction' }

=head3 MESSAGES

    Message                         Meaning                       What to do
    ------------------------------  ----------------------------  ------------------------------
    _emit() is a protected method   called from outside the class Call it from a subclass only
    ... (croak)                     and its subclasses

=cut

sub _emit :Protected {
	my ($self, $text) = @_;

	my $tb = Test::Builder->new();
	my $handle = $tb->in_todo() ? $tb->todo_output() : $tb->failure_output();
	my $layered = grep { /\A(?:utf8|encoding)/ } PerlIO::get_layers($handle);
	# A flagged string is characters, which a raw handle needs as UTF-8;
	# an unflagged string is already bytes and is printed untouched
	$text = Encode::encode('UTF-8', $text) if(!$layered && utf8::is_utf8($text));
	$tb->diag($text);

	return $self;
}

=head2 i18n

Make one of this module's messages, in the logger's language.

=head3 Purpose

All the text that this module shows to people comes from here.  So the
text can be translated, or changed, without changing the code.

=head3 Args

=over 4

=item * C<$key> - the name of the message, such as C<needs_pattern>.

=item * C<\%args> - optional.  Values for the placeholders in the message.
C<class> is filled in for you (the logger's class).  C<count> chooses the
singular or plural form.  C<gender> chooses a gender form.

=back

=head3 How a message template works

A template is a string.  C<%{name}s> is replaced by the value called
C<name>.  After the name you can use any C<sprintf> format letter, for
example C<%{count}d> or C<%{ratio}.2f>.  C<%%> gives one C<%>.  A value
that is missing becomes the text C<undef>, with no warning.

A template can also be a hash.  The keys are gender names (such as
C<male>, C<female>) or plural forms (C<zero>, C<one>, C<two>, C<few>,
C<many>, C<other>).  The values are templates, so they can be hashes too.
C<other> is used when nothing else fits.  C<zero> is used for a count of
0, if it is there.

    {
        zero  => 'no messages',
        one   => '%{count}d message',
        other => '%{count}d messages',
    }

=head3 Where the template is found

The first one found is used:

=over 4

=item 1. Your C<i18n> option, in the logger's language.

=item 2. This module's messages, in the logger's language.

=item 3. Your C<i18n> option, in English.

=item 4. This module's messages, in English.

=back

If the key is not found anywhere, the key itself is returned.

=head3 Returns

The finished message, as a Perl character string.

=head3 Side Effects

None.

=head3 EXAMPLE

    # Inside a subclass
    my $text = $self->i18n('needs_pattern', { method => 'like' });
    # "Test::Log::Abstraction: like() needs a pattern"

    # Your own message, with gender and plural forms.  i18n() is
    # protected, so call it from a method of your subclass.
    my $logger = My::Logger->new(i18n => {
        en => {
            logged => {
                male => { one => 'He logged %{count}d line', other => 'He logged %{count}d lines' },
                other => 'They logged %{count}d lines',
            },
        },
    });
    # In a method of My::Logger:
    $self->i18n('logged', { gender => 'male', count => 2 });    # 'He logged 2 lines'

=head3 API SPECIFICATION

=head4 Input

    {
        key => { type => 'string', position => 0 },
        args => { type => 'hashref', optional => 1, position => 1 },
    }

=head4 Output

    { type => 'string' }

=head3 MESSAGES

None.  It always returns a string.

=head3 PSEUDOCODE

    language = the logger's language (for a class name: the configured one)
    template = the first one found in the four places listed above
    if no template was found, return the key
    while the template is a hash:
        choose by gender, else by plural form, else 'other'
    replace each %{name}format with sprintf(format, the value of name)
    return the text

=cut

sub i18n :Protected {
	my ($self, $key, $args) = @_;

	# Documented always to return a string: an undefined key renders as '',
	# a reference key as its string form, and arguments that are not a hash
	# are ignored
	$key = defined($key) ? "$key" : '';
	my $class = ref($self) || $self;
	my %args = (class => $class, ((ref($args) eq 'HASH') ? %{$args} : ()));
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
# Side effects: None.  Each step descends one level, and a hash already
#               visited ends the walk, so even a cyclic template terminates.
sub _variant {
	my ($template, $args, $lang) = @_;

	my %visited;
	while(ref($template) eq 'HASH') {
		# A template from the i18n option may contain itself
		return '' if($visited{Scalar::Util::refaddr($template)}++);
		my $gender = $args->{'gender'};
		my $form = (defined($gender) && exists($template->{$gender})) ? $gender : _plural($template, $args->{'count'}, $lang);
		$template = exists($template->{$form}) ? $template->{$form} : '';
	}

	# A form given as undef in the i18n option renders as nothing
	return defined($template) ? $template : '';
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
	my $numeric = defined($count) && !ref($count) && Scalar::Util::looks_like_number($count);
	my $rule = (defined($lang) && exists($PLURAL{$lang})) ? $PLURAL{$lang} : $PLURAL{$FALLBACK_LANG};
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

	# Mark a translated template as characters, so _emit() encodes it even
	# when every character is below 0x100, as in French and German
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
# Side effects: None; never warns or dies, and leaves $@ alone.
sub _format {
	my ($percent, $conversion, $value) = @_;

	# Infinity and NaN look like numbers, but %d would print them as -1.
	# References are never numbers: looks_like_number() would call an
	# object's overloading, which may die
	my $numeric = defined($value) && !ref($value) && Scalar::Util::looks_like_number($value) && ($value == $value) && (abs($value) != 9**9**9);
	# An object whose overloaded "" dies is shown in plain form, as in
	# _stringify(), so a message can always be built
	local $@;
	my $text = defined($percent) ? '%'
		: !defined($value) ? 'undef'
		: ($numeric || ($conversion =~ /s\z/)) ? eval { no warnings qw(uninitialized); sprintf("%$conversion", $value) }	## no critic (ProhibitNoWarnings)
		: $value;

	return defined($text) ? $text : overload::StrVal($value);
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

=item * B<It accepts more than the real logger.>  The syslog names
(C<warning>, C<err>, C<crit>, C<emerg>, C<panic>, C<informational>) are
methods here, but not in L<Log::Abstraction> 0.39.  Code that calls them
passes its tests, and then stops with an error in production.  They are
kept for the old MyLogger code.  A C<strict> option, which allows only the
real L<Log::Abstraction> methods, would be safer.

=item * B<Messages are stored under the name that was called.>  See
L</COMMON PITFALLS>.  Your test must use the same name as the code under
test.

=item * B<C<level()> does not hide messages.>  L<Log::Abstraction> drops
messages below its level.  This module stores them all, which is usually
what a test wants.

=item * B<Message text is not always the same as in L<Log::Abstraction>.>
C<undef> becomes C<undef> instead of being dropped, and hashes and arrays
are written out as data.  A test that compares the exact text may give a
different result with the real logger.

=item * B<Mixed encodings in translated output.>  See L</ENCODING>.

=item * B<The access checks are off under C<prove>.>  L<Sub::Private> and
L<Sub::Protected> do not check anything when C<$ENV{HARNESS_ACTIVE}> is
set, and C<prove> always sets it.  They do check under a plain
C<perl t/foo.t>.  Turning this off would change a setting that is shared
by every module, and that would break the tests of other modules.

=item * B<Many modules are needed.>  L<Params::Validate::Strict>,
L<Sub::Private>, L<Sub::Protected>, L<Readonly>, and L<autodie> (with
L<IPC::System::Simple>) must be installed, for what is a small test
helper.  L<Object::Configure> is not used, because it loads
L<Log::Abstraction>, and a test logger should not need that.

=item * B<Simple translation system.>  L<Locale::Maketext> uses numbered
placeholders and has no gender forms.  Modules based on gettext need
compiled files.  Neither fits a small table with named placeholders, so
this module has its own.  Native speakers have not yet checked the
German, French and Chinese texts.

=item * B<Slow patterns are not stopped.>  C<like> and C<unlike> run the
pattern against every stored message.  A pattern with nested quantifiers,
such as C<qr/(a+)+$/>, can take a very long time on some messages.  This
module does not limit the time.

=item * B<One process only.>  Messages are kept in the memory of the
logger object.  Messages logged in a child process (after C<fork>) are not
seen by the parent.

=back

=head1 DIAGNOSTICS

Each method lists its messages under C<MESSAGES>.  All messages can be
translated or changed; see L</i18n>.

=head1 SEE ALSO

L<Log::Abstraction>, L<Test::Builder>, L<Test::Most>

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=encoding utf8

=head1 FORMAL SPECIFICATION

This section describes each method in the Z notation.  You do not need it
to use the module.  It is here so that the behaviour is exact.

=head2 State

    [TEXT, NAME, KEY, TEMPLATE]
    BOOL ::= true | false
    LANG == { en, de, fr, zh }
    SEVERITY == 0 .. 7

    severity : NAME ⇸ SEVERITY
    catalogue : LANG ⇸ (KEY ⇸ TEMPLATE)

    Entry ≙ [ level : NAME; message : TEXT; fields : TEXT ⇸ TEXT ]

    Logger
      log       : seq Entry
      verbose   : BOOL
      threshold : SEVERITY
      lang      : LANG

C<severity> is the level table under L</Levels and how serious they are>.
C<catalogue> is the built-in message table.  C<ΔLogger> means the method
may change the state; C<ΞLogger> means it does not.

=head2 new

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
      clone! : Logger
      ─────────
      clone!.log = log
      clone!.verbose = verbose
      clone!.threshold = threshold
      clone!.lang = lang

C<Clone> is C<< $logger->new() >> with no options.  Options that are given
replace the matching values, as in C<New>.

=head2 trace, debug, info, notice, warn, error, fatal, critical, alert, emergency

    Log
      ΔLogger
      name? : NAME
      text? : TEXT
      ─────────
      name? ∈ dom severity
      log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩
      verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang

=head2 is_trace, is_debug, is_info, is_notice, is_warn, is_error, is_critical, is_alert, is_emergency

    IsLevel
      ΞLogger
      name? : NAME
      result! : BOOL
      ─────────
      name? ∈ dom severity
      result! = true ⇔ severity name? ≤ threshold

=head2 AUTOLOAD

    Unknown
      ΔLogger
      name? : NAME
      text? : TEXT
      ─────────
      name? ∉ dom severity
      log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩
      verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang

=head2 messages

    Messages
      ΞLogger
      result! : seq Entry
      ─────────
      result! = log

=head2 clear

    Clear
      ΔLogger
      ─────────
      log' = ⟨⟩
      verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang

=head2 count

    Count
      ΞLogger
      level? : NAME
      result! : ℕ
      ─────────
      result! = # (log ↾ { e : Entry | e.level = level? })

    CountAll
      ΞLogger
      result! : ℕ
      ─────────
      result! = # log

=head2 like

    Like
      ΞLogger
      pattern? : ℙ TEXT
      result! : BOOL
      ─────────
      result! = true ⇔ (∃ e : ran log • e.message ∈ pattern?)

=head2 unlike

    Unlike
      ΞLogger
      pattern? : ℙ TEXT
      result! : BOOL
      ─────────
      result! = true ⇔ (∀ e : ran log • e.message ∉ pattern?)

=head2 has_level

    HasLevel
      ΞLogger
      level? : NAME
      result! : BOOL
      ─────────
      result! = true ⇔ (∃ e : ran log • e.level = level?)

=head2 empty

    Empty
      ΞLogger
      result! : BOOL
      ─────────
      result! = true ⇔ log = ⟨⟩

=head2 verbose

    SetVerbose
      ΔLogger
      value? : BOOL
      result! : BOOL
      ─────────
      verbose' = value?
      result! = verbose'
      log' = log ∧ threshold' = threshold ∧ lang' = lang

    GetVerbose
      ΞLogger
      result! : BOOL
      ─────────
      result! = verbose

=head2 level

    SetLevel
      ΔLogger
      name? : NAME
      ─────────
      name? ∈ dom severity ⇒ threshold' = severity name?
      name? ∉ dom severity ⇒ threshold' = threshold
      log' = log ∧ verbose' = verbose ∧ lang' = lang

    GetLevel
      ΞLogger
      result! : SEVERITY
      ─────────
      result! = threshold

=head2 flush

    Flush
      ΞLogger

=head2 lang

    Lang
      ΞLogger
      result! : LANG
      ─────────
      result! = lang

=head2 i18n

    I18n
      ΞLogger
      key? : KEY
      result! : TEXT
      ─────────
      key? ∈ dom (catalogue lang) ⇒ result! = render (catalogue lang key?)
      key? ∉ dom (catalogue lang) ∧ key? ∈ dom (catalogue en) ⇒
          result! = render (catalogue en key?)
      key? ∉ dom (catalogue lang) ∪ dom (catalogue en) ⇒ result! = key?

C<render> fills in the placeholders.  The C<i18n> option is searched
before C<catalogue> in each language.

=head1 STATE DIAGRAM

A logger has two main states: B<EMPTY> (no stored messages) and
B<CAPTURING> (one or more stored messages).  Two settings, B<verbose> and
B<level>, can change in either state; they do not move the logger between
states.  Methods that only read or test (C<like>, C<count>, C<is_debug>,
and so on) never change the state.

                  new(%options)
                  [check options; choose language,
                   diag rule and level]
                        |
                        | invalid option
                        +----------------------> croak, no logger made
                        |
                        v
    +-----------------------------------------+
    |                 EMPTY                   |<----------------+
    |  messages = ()                          |                 |
    +-----------------------------------------+                 |
         |                                                      |
         | trace() ... emergency(), warning() ... panic()       | clear()
         | [store the message; print it if the diag rule        | [delete all
         |  or verbose allows; $@ and $! are kept]              |  messages;
         |                                                      |  return the
         | wran() or any unknown method (AUTOLOAD)              |  logger]
         | [store under that name; always print                 |
         |  "no method 'wran'"]                                 |
         v                                                      |
    +-----------------------------------------+                 |
    |               CAPTURING                 |-----------------+
    |  messages = (m1, m2, ...)               |
    +-----------------------------------------+
         |       ^
         |       | any level method, or an unknown method
         +-------+ [store one more message; maybe print it]

    Changes allowed in BOTH states (the state stays the same):

      verbose(1) / verbose(0)   verbose on / off
                                [from now on: print every message / use
                                 the diag rule]
      level('error')            level number = 3
                                [the is_* answers change; nothing is
                                 hidden]
      level('bogus')            no change [warning; returns undef]

    Read-only calls in BOTH states (the state stays the same):

      like, unlike, has_level, empty
                                [one TAP result; on failure, print the
                                 messages that explain it]
      count, messages, lang, is_trace ... is_emergency, flush
                                [return a value only]
      like(undef), has_level(undef), a bad argument, or any method
      called on something that is not a logger (the class name, undef,
      a plain reference, or another class's object)
                                [croak; no change]

    Copying (the original logger does not change):

      EMPTY     --- $logger->new(%options) ---> a new logger in EMPTY
      CAPTURING --- $logger->new(%options) ---> a new logger in CAPTURING
                    [the new logger has copies of the messages, and the
                     same verbose and level, unless new values are given]

    End:

      EMPTY or CAPTURING --- the last reference goes away ---> destroyed
                    [DESTROY does nothing; nothing is stored or printed]

=head1 LICENCE AND COPYRIGHT

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.

=cut

1;
