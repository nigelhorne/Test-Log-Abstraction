## Name

Test::Log::Abstraction - Capture log output in tests and assert on it

## Version

0.002.0

## Synopsis

```perl
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
```

## Description

A test double for [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction), usable wherever code under test is
passed a `logger =>` object.

Every level method that [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) offers (`trace`, `debug`,
`info`, `notice`, `warn`, `error`, `fatal`, `critical`, `alert` and
`emergency`), plus the syslog spellings `warning`, `err`, `crit`,
`emerg`, `panic` and `informational`, records the message instead of
writing it anywhere, and optionally sends it to TAP diagnostics.  Nothing is
ever written to disk, and no logging backend is loaded.

The non-logging parts of the [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) API that code under test is
likely to call - `level()`, the `is_<level>()` predicates,
`messages()` and `flush()` - are also implemented, so they are not
mistaken for unknown log levels.

### Diagnostics

Messages at `warning` and above are printed with ["diag" in Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder#diag) by
default, so a test that accidentally triggers a warning is visible; `trace`,
`debug`, `info` and `notice` are printed only in verbose mode.  Verbose
mode is on when `verbose => 1` is passed to `new()`, or when
`$ENV{TEST_VERBOSE}` (set by `prove -v`) or `$ENV{VERBOSE}` is true.

Change it with the `diag` option: `'all'` prints everything,
`'none'` prints nothing (unless verbose), a level name such as `'error'`
prints that level and everything more severe, and an array reference prints
just those levels.

When an assertion (`like`, `unlike`, `has_level`, `empty`) fails, the
captured messages that explain the failure are printed as diagnostics, so
the reason is visible without re-running the test.

### Language

The module's own messages (errors, warnings and failure diagnostics) are
available in English (`en`), German (`de`), French (`fr`) and Simplified
Chinese (`zh`).  The language is chosen, in order of precedence, from the
`lang` option, the `country` option (an ISO 3166 two-letter code), the
`LC_ALL`, `LC_MESSAGES` or `LANG` environment variables when
`lang => 'auto'`, and finally `$Test::Log::Abstraction::config{lang}`
(`en`).  English is the default, rather than the environment, so that test
output - and tests that match on it - are the same on every machine.
Missing translations fall back to English, key by key.  Templates can be
added or overridden with the `i18n` option.

### Configuration

Defaults live in the package hash `%Test::Log::Abstraction::config`, a
flat hash of the same keys that `new()` takes, so it can be filled from
[Object::Configure](https://metacpan.org/pod/Object%3A%3AConfigure) or set directly:

```
$Test::Log::Abstraction::config{'diag'} = 'none';
```

### Formal Model

The formal specifications below share this state, in Z notation:

```
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
```

`severity` is the table of known level names: `emergency`, `emerg` and
`panic` are 0; `alert` 1; `critical`, `crit` and `fatal` 2;
`error` and `err` 3; `warning` and `warn` 4; `notice` 5; `info` and
`informational` 6; `debug` and `trace` 7.

### Migrating From T/Lib/MyLogger.pm

Replace, in each test file:

```perl
use lib 't/lib';
use MyLogger;
...
logger => MyLogger->new()
```

with:

```perl
use Test::Log::Abstraction;
...
logger => Test::Log::Abstraction->new()
```

and delete `t/lib/MyLogger.pm`.  Unlike the old MyLogger copies, this
implementation is identical everywhere, never recurses when a level method is
called with `undef` (see `t/autoload.t`), and records every message so
tests can assert on it instead of only printing it.

## Methods

### New

Creates a logger.

#### Purpose

Build a test double that captures everything logged to it.

#### Args

All optional, as a hash or a hash reference:

- `verbose` - true to print every message.  Defaults to
`$ENV{TEST_VERBOSE} || $ENV{VERBOSE}`.
- `diag` - which messages to print: `'all'`, `'none'`, a level
name (that level and more severe), or an array reference of level names.
Defaults to `'warning'`.
- `level` - the threshold that `level()` and `is_<level>()`
report.  Defaults to `'trace'`, so all `is_*` predicates are true and the
code under test exercises its debug paths.  It does not filter capture.
- `lang` - language of this module's own messages, or `'auto'` to
read `LC_ALL`, `LC_MESSAGES` and `LANG`.
- `country` - ISO 3166 two-letter country code used to choose the
language when `lang` is not given; case-insensitive.
- `i18n` - `{ lang => { key => template } }` to add or override
message templates (see ["i18n"](#i18n)).

Any other options are accepted and ignored, as ["new" in Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction#new)
takes a configuration hash that the double does not need.  An odd-length
argument list is ignored rather than fatal, for compatibility with the
MyLogger copies this module replaces.

Called on an existing logger, it makes a clone: the same options, overridden
by any passed, the current `verbose` and `level` settings, and a copy of
the captured messages, as ["new" in Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction#new) does.  It may also be
called as a function, `Test::Log::Abstraction::new(%options)`.

#### Returns

The new logger.

#### Side Effects

Reads `%ENV` for verbosity and, with `lang => 'auto'`, the locale.

#### Example

```perl
my $logger = Test::Log::Abstraction->new();
my $quiet = Test::Log::Abstraction->new(diag => 'none');
my $german = Test::Log::Abstraction->new({ country => 'DE' });
my $clone = $logger->new(diag => 'all');
```

#### Api Specification

##### Input

```perl
{
    verbose => { type => 'scalar', optional => 1 },
    diag => { type => ['string', 'arrayref'], optional => 1 },
    level => { type => 'string', optional => 1 },
    lang => { type => 'string', optional => 1 },
    country => { type => 'string', optional => 1, matches => qr/\A[A-Za-z]{2}\z/ },
    i18n => { type => 'hashref', optional => 1 },
}
```

##### Output

```perl
{ type => 'object', isa => 'Test::Log::Abstraction' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
invalid diag level 'X'          X is not a level name       Use a name from the level list
diag must be a level name ...   diag is a hash or code ref  Pass a string or an array ref
invalid syslog level 'X'        level option is unknown     Use a name from the level list
invalid argument: ...           an option has the wrong     Fix the option's type or value
                                type or format
```

All are fatal (`croak`).

#### Formal Specification

```
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
```

#### Pseudocode

```
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
```

### Trace, Debug, Info, Notice, Warn, Error, Fatal, Critical, Alert, Emergency

Record a message at that level.

#### Purpose

Every [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) level, and the syslog spellings `warning`, `err`,
`crit`, `emerg`, `panic` and `informational`, is a method that records
the call and, subject to the `diag` setting, prints it.

- `trace`, `debug`, `info`, `informational`, `notice`

    Captured; printed only in verbose mode by default.

- `warn`, `warning`, `error`, `err`, `critical`, `crit`,
`fatal`, `alert`, `emergency`, `emerg`, `panic`

    Captured and printed by default.

#### Args

Following [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction)'s rules: the arguments are concatenated into
the message and a trailing newline removed; a single array reference is a
list of message parts; a hash reference at the end of two or more arguments
is captured, copied, as structured `fields` (an empty one is dropped).
Unlike [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction), a lone hash reference is rendered as sorted
`{key => value}` pairs and nested array references as `[a, b]`, so
they can be matched, and `undef` becomes the string `undef` instead of
being dropped, so that it is visible.

#### Returns

The logger, as [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) does, so calls can be chained.

#### Side Effects

Appends one entry to `messages()`; may print a diagnostic.  `$@` and
`$!` are preserved, so logging inside an error handler cannot change the
error being handled.

#### Example

```perl
$logger->warn('something looks wrong');
$logger->info('started', { pid => $$ });
$logger->error({ error => 'cannot open file' });
$logger->debug(['part 1, ', 'part 2']);
```

#### Api Specification

##### Input

```perl
{ type => 'arrayref', optional => 1 }    # any list of values
```

##### Output

```perl
{ type => 'object', isa => 'Test::Log::Abstraction' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
X() must be called on an        called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Log
  ΔLogger
  name? : NAME
  text? : TEXT
  ─────────
  name? ∈ dom severity
  log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩
  verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang
```

### Is\_Trace, Is\_Debug, Is\_Info, Is\_Notice, Is\_Warn, Is\_Error, Is\_Critical, Is\_Alert, Is\_Emergency

Whether a level is enabled.

#### Purpose

Mirror [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction)'s predicates, so that code which guards an
expensive log call with `if($logger->is_debug())` runs that call under
test.

#### Args

None.

#### Returns

1 if the threshold set with `level` admits that level, else 0.  With the
default threshold, `trace`, every predicate is 1.

#### Side Effects

None.

#### Example

```
$logger->level('warning');
$logger->is_warn();    # 1
$logger->is_info();    # 0
```

#### Api Specification

##### Input

```
{}
```

##### Output

```perl
{ type => 'boolean' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
X() must be called on an        called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
IsLevel
  ΞLogger
  name? : NAME
  result! : BOOL
  ─────────
  result! = true ⇔ threshold ≥ severity name?
```

### Autoload

Catch calls to methods that do not exist.

#### Purpose

Any other method call - typically a level name that does not exist, such as
a typo - captures the message under that name and prints a notice that the
diag setting cannot suppress, instead of dying part way through a test.  A
typo'd level therefore cannot pass silently.

#### Args

As for a level method.

#### Returns

The logger.

#### Side Effects

Records an entry with the called name as its level, and prints
`no method 'name'`.

#### Example

```
$logger->wran('oops');    # captured as level 'wran', notice printed
```

#### Api Specification

##### Input

```perl
{ type => 'arrayref', optional => 1 }
```

##### Output

```perl
{ type => 'object', isa => 'Test::Log::Abstraction' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
no method 'X'                   X is not a method or level  Fix the method name
X() must be called on an        unknown class method        Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Unknown
  ΔLogger
  name? : NAME
  text? : TEXT
  ─────────
  name? ∉ dom severity
  log' = log ⁀ ⟨⟨ level ↦ name?, message ↦ text? ⟩⟩
```

### Messages

The captured messages.

#### Purpose

Let a test inspect everything that was logged.

#### Args

None.

#### Returns

A reference to a new array of `{ level, message }` hash references, in
the order they were logged; entries logged with structured fields also have
a `fields` hash reference.  The array is a copy, as in
[Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction), so changing it does not change the capture.

#### Side Effects

None.

#### Example

```perl
foreach my $entry (@{ $logger->messages() }) {
    diag("$entry->{level}: $entry->{message}");
}
```

#### Api Specification

##### Input

```
{}
```

##### Output

```perl
{ type => 'arrayref' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
messages() must be called on    called on the class name    Call it on a logger object
an object, not on the class
```

#### Formal Specification

```
Messages
  ΞLogger
  result! : seq Entry
  ─────────
  result! = log
```

### Clear

Forget the captured messages.

#### Purpose

Reset between phases of a test.

#### Args

None.

#### Returns

The logger, for chaining.

#### Side Effects

Empties the capture.

#### Example

```
$logger->clear()->empty('nothing logged yet');
```

#### Api Specification

##### Input

```
{}
```

##### Output

```perl
{ type => 'object', isa => 'Test::Log::Abstraction' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
clear() must be called on an    called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Clear
  ΔLogger
  ─────────
  log' = ⟨⟩
  verbose' = verbose ∧ threshold' = threshold ∧ lang' = lang
```

### Count

How many messages were captured.

#### Purpose

Assert on the volume of logging.

#### Args

- `$level` - optional; count only that level (case-insensitive).
Aliases are distinct: `count('warn')` does not count `warning` calls.

#### Returns

The number of matching messages.

#### Side Effects

None.

#### Example

```
is($logger->count(), 3, 'three messages');
is($logger->count('error'), 1, 'one error');
```

#### Api Specification

##### Input

```perl
{ level => { type => 'string', optional => 1 } }
```

##### Output

```perl
{ type => 'integer', min => 0 }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
count() must be called on an    called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Count
  ΞLogger
  level? : NAME
  result! : ℕ
  ─────────
  result! = # (log ↾ { e : Entry | e.level = level? })
```

### Like

Assert that a message matches.

#### Purpose

Pass if any captured message matches the pattern.

#### Args

- `$pattern` - a `qr//` or a string, used as a regular expression.
- `$name` - optional test name.

#### Returns

The test result.

#### Side Effects

Reports a test through [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder), so count it in your plan (or use
`done_testing()`).  On failure, lists the captured messages as
diagnostics.

#### Example

```
$logger->like(qr/updated/, 'the update was logged');
```

#### Api Specification

##### Input

```perl
{
    pattern => { type => ['regex', 'string'] },
    name => { type => 'string', optional => 1 },
}
```

##### Output

```perl
{ type => 'boolean' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
like() needs a pattern          no pattern was given        Pass a qr// or a string
invalid argument: ...           pattern is not a regex      Pass a qr// or a string
                                or a string
N messages were captured:       (diagnostic) the test       Compare the listed messages
                                failed                      with the pattern
```

#### Formal Specification

```
Like
  ΞLogger
  pattern? : ℙ TEXT
  result! : BOOL
  ─────────
  result! = true ⇔ (∃ e : ran log • e.message ∈ pattern?)
```

### Unlike

Assert that no message matches.

#### Purpose

Pass if no captured message matches the pattern.

#### Args

- `$pattern` - a `qr//` or a string, used as a regular expression.
- `$name` - optional test name.

#### Returns

The test result.

#### Side Effects

Reports a test through [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder).  On failure, lists the messages
that matched as diagnostics.

#### Example

```
$logger->unlike(qr/fatal/, 'nothing fatal was logged');
```

#### Api Specification

##### Input

```perl
{
    pattern => { type => ['regex', 'string'] },
    name => { type => 'string', optional => 1 },
}
```

##### Output

```perl
{ type => 'boolean' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
unlike() needs a pattern        no pattern was given        Pass a qr// or a string
invalid argument: ...           pattern is not a regex      Pass a qr// or a string
                                or a string
N messages matched:             (diagnostic) the test       Look at the listed messages
                                failed
```

#### Formal Specification

```
Unlike
  ΞLogger
  pattern? : ℙ TEXT
  result! : BOOL
  ─────────
  result! = true ⇔ (∀ e : ran log • e.message ∉ pattern?)
```

### Has\_Level

Assert that a level was logged.

#### Purpose

Pass if at least one message was logged at that level.

#### Args

- `$level` - level name, case-insensitive.  Aliases are distinct:
`has_level('warn')` does not see `warning` calls.
- `$name` - optional test name.

#### Returns

The test result.

#### Side Effects

Reports a test through [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder).  On failure, lists the captured
messages as diagnostics.

#### Example

```
$logger->has_level('error', 'the failure was logged');
```

#### Api Specification

##### Input

```perl
{
    level => { type => 'string' },
    name => { type => 'string', optional => 1 },
}
```

##### Output

```perl
{ type => 'boolean' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
has_level() needs a level name  no level was given          Pass a level name
invalid argument: ...           level is not a string       Pass a level name
N messages were captured:       (diagnostic) the test       Look at the listed levels
                                failed
```

#### Formal Specification

```
HasLevel
  ΞLogger
  level? : NAME
  result! : BOOL
  ─────────
  result! = true ⇔ (∃ e : ran log • e.level = level?)
```

### Empty

Assert that nothing was logged.

#### Purpose

The usual assertion after a clean run.

#### Args

- `$name` - optional test name.

#### Returns

The test result.

#### Side Effects

Reports a test through [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder).  On failure, lists the captured
messages as diagnostics.

#### Example

```
$logger->empty('nothing was logged');
```

#### Api Specification

##### Input

```perl
{ name => { type => 'string', optional => 1 } }
```

##### Output

```perl
{ type => 'boolean' }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
N messages were captured:       (diagnostic) the test       Look at the listed messages
                                failed
```

#### Formal Specification

```
Empty
  ΞLogger
  result! : BOOL
  ─────────
  result! = true ⇔ log = ⟨⟩
```

### Verbose

Get or set verbose mode.

#### Purpose

Print every message, whatever the `diag` rule, while debugging a test.

#### Args

- `$value` - optional; true to turn verbose mode on.

#### Returns

The current setting, 1 or 0, after any change.

#### Side Effects

Changes the setting when given an argument.

#### Example

```perl
$logger->verbose(1);
my $verbose = $logger->verbose();
```

#### Api Specification

##### Input

```perl
{ value => { type => 'scalar', optional => 1 } }
```

##### Output

```perl
{ type => 'integer', min => 0, max => 1 }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
verbose() must be called on an  called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Verbose
  ΔLogger
  value? : BOOL
  result! : BOOL
  ─────────
  verbose' = value?
  result! = verbose'
  log' = log ∧ threshold' = threshold ∧ lang' = lang
```

### Level

Get or set the level threshold.

#### Purpose

Mirror ["level" in Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction#level), for code under test that reads or
changes it.  The threshold only affects the `is_<level>()`
predicates: every message is still captured.

#### Args

- `$name` - optional level name, case-insensitive.

#### Returns

Without an argument, the numeric threshold (0 to 7).  With a valid name, the
logger, for chaining.  With an invalid name, `undef`, as
[Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) does.

#### Side Effects

Changes the threshold; carps on an invalid name.

#### Example

```
$logger->level('error');
print $logger->level();    # 3
```

#### Api Specification

##### Input

```perl
{ name => { type => 'string', optional => 1 } }
```

##### Output

```perl
{ type => ['integer', 'object'], optional => 1 }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
invalid syslog level 'X'        X is not a level name       Use a name from the level list
                                (warning)
```

#### Formal Specification

```
SetLevel
  ΔLogger
  name? : NAME
  ─────────
  name? ∈ dom severity ⇒ threshold' = severity name?
  name? ∉ dom severity ⇒ threshold' = threshold
  log' = log
```

### Flush

Does nothing.

#### Purpose

["flush" in Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction#flush) sends held e-mail digests; the double has none,
but code under test may call it.

#### Args

None.

#### Returns

The logger, for chaining.

#### Side Effects

None.

#### Example

```
$logger->flush();
```

#### Api Specification

##### Input

```
{}
```

##### Output

```perl
{ type => 'object', isa => 'Test::Log::Abstraction' }
```

#### Messages

None.

#### Formal Specification

```
Flush
  ΞLogger
```

### Lang

Which language the logger's own messages are in.

#### Purpose

Let a test check the outcome of the `lang` and `country` options.

#### Args

None.

#### Returns

A language tag: `en`, `de`, `fr`, `zh`, or one supplied with the
`i18n` option.

#### Side Effects

None.

#### Example

```perl
my $lang = Test::Log::Abstraction->new(country => 'FR')->lang();    # 'fr'
```

#### Api Specification

##### Input

```
{}
```

##### Output

```perl
{ type => 'string', matches => qr/\A[a-z]{2,3}\z/ }
```

#### Messages

```
Message                         Meaning                     Resolution
------------------------------  --------------------------  -----------------------------
lang() must be called on an     called on the class name    Call it on a logger object
object, not on the class
```

#### Formal Specification

```
Lang
  ΞLogger
  result! : LANG
  ─────────
  result! = lang
```

## Protected Methods

Callable from this class and its subclasses only ([Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected));
subclasses may override them.

### \_Emit

```perl
$self->_emit($text);
```

Sends one line to TAP diagnostics through [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder), so it works in
tests that never loaded [Test::More](https://metacpan.org/pod/Test%3A%3AMore).  A string with characters above
`0xFF` is UTF-8 encoded first, unless the output handle already has an
encoding layer, so that a translated message never warns
`Wide character in print`.  Returns the logger.  Override it to send
captured messages somewhere else.

### i18n

Render one of this module's messages in the logger's language.

#### Purpose

The single source of every user-facing string, so that messages can be
translated and overridden without touching the code.

#### Args

- `$key` - message key, such as `needs_pattern`.
- `\%args` - optional values for the template's placeholders.
`class` defaults to the invocant's class.  `count` selects a plural form
and `gender` a gender form, when the template has them.

A template is a string with `%{name}s`-style placeholders, where any
`sprintf` conversion (`%{count}d`, `%{ratio}.2f`) may follow the name,
and `%%` is a literal `%`.  A missing value is rendered as `undef`,
without a warning.  Instead of a string, a template may be a hash reference
keyed by gender (`male`, `female`, ...) or by plural category (`zero`,
`one`, `two`, `few`, `many`, `other`); these nest, and `other` is the
fallback.  `zero` is used for a count of 0 when present, whatever the
language's rules.

The template is looked up in the `i18n` option, then the built-in
catalogue, first for the logger's language and then for English; an unknown
key is returned as it is.

#### Returns

The message, as a character string.

#### Side Effects

None.

#### Example

```perl
my $text = $self->i18n('needs_pattern', { method => 'like' });
# "Test::Log::Abstraction: like() needs a pattern"

my $logger = Test::Log::Abstraction->new(i18n => {
    en => { greeting => { male => 'He logged %{count}d', female => 'She logged %{count}d' } },
});
```

#### Api Specification

##### Input

```perl
{
    key => { type => 'string' },
    args => { type => 'hashref', optional => 1 },
}
```

##### Output

```perl
{ type => 'string' }
```

#### Messages

None; it never fails.

#### Formal Specification

```
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
```

#### Pseudocode

```
language = the logger's, or the configured one for a class
template = first of: i18n option[language][key], catalogue[language][key],
           i18n option[en][key], catalogue[en][key]
if there is no template, return the key
while the template is a hash: choose by gender, then by plural, then 'other'
replace each %{name}conversion with sprintf(conversion, args[name])
```

## Limitations

- **More lenient than the real thing.**  The syslog spellings
(`warning`, `err`, `crit`, `emerg`, `panic`, `informational`) are
methods here but not in [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) 0.39, so code that calls them
passes its tests and then dies in production.  They are kept for the
MyLogger code this module replaces; a `strict` option that limits the
double to [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction)'s real API would be safer.
- **Aliases are recorded under the name called.**  `count('warn')`
and `has_level('warn')` do not see `warning` calls, and `fatal` is
recorded as `fatal` where [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) records `error`.  Tests
must assert on the spelling the code under test uses.
- **`level()` does not filter.**  The threshold only drives the
`is_*` predicates; every message is captured whatever it is, which is
what a test usually wants but is not what [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) does.
- **Rendering differs on purpose.**  `undef` becomes `undef`
rather than being dropped, and hash and array references are rendered as
data, so an exact-match assertion written against this double may not hold
against [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) output, and the reverse.
- **Mixed encodings in diagnostics.**  A translated (non-English)
diagnostic that embeds a message logged as undecoded UTF-8 bytes is
printed double-encoded, because the bytes are taken to be Latin-1 when
joined to the character-string template.  English output is unaffected.
- **Encapsulation is not enforced under a harness.**  [Sub::Private](https://metacpan.org/pod/Sub%3A%3APrivate)
and [Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected) skip their checks when `$ENV{HARNESS_ACTIVE}` is set,
which is always the case for a module that only runs inside tests.  The
checks apply under a plain `perl t/foo.t`.  Turning the bypass off would
mean changing their process-wide configuration, which would break other
modules' white-box tests.
- **Dependency weight.**  [Params::Validate::Strict](https://metacpan.org/pod/Params%3A%3AValidate%3A%3AStrict),
[Sub::Private](https://metacpan.org/pod/Sub%3A%3APrivate), [Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected), [Readonly](https://metacpan.org/pod/Readonly) and [autodie](https://metacpan.org/pod/autodie) (with
[IPC::System::Simple](https://metacpan.org/pod/IPC%3A%3ASystem%3A%3ASimple)) are runtime dependencies of what is otherwise a
small test helper.  [Object::Configure](https://metacpan.org/pod/Object%3A%3AConfigure) is deliberately not used:
it loads [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction) itself, which a test double must not need.
- **Home-grown i18n.**  [Locale::Maketext](https://metacpan.org/pod/Locale%3A%3AMaketext) uses positional bracket
notation and has no gender support, and gettext-based modules need compiled
catalogues; neither fits a small, named-placeholder table.  The four
catalogues were written without review by native speakers.
- **Single-process only.**  Messages are kept in memory in the
logger object; output logged in a child process is not seen by the parent.

## Diagnostics

See the `MESSAGES` section of each method.  The messages can be translated
or overridden; see ["i18n"](#i18n).

## See Also

[Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction), [Test::Builder](https://metacpan.org/pod/Test%3A%3ABuilder), [Test::Most](https://metacpan.org/pod/Test%3A%3AMost)

## Author

Nigel Horne, `<njh at nigelhorne.com>`

## Licence and Copyright

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.
