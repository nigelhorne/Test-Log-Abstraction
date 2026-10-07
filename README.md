# NAME

Test::Log::Abstraction - Capture log output in tests and assert on it

# VERSION

Version 0.01

# SYNOPSIS

    use Test::Most;
    use Test::Log::Abstraction;

    my $logger = Test::Log::Abstraction->new();
    my $obj = Some::Class->new(logger => $logger);

    $obj->do_something();

    # Assertions on what was logged
    $logger->like(qr/updated/, 'do_something() logs that it updated');
    $logger->has_level('error');
    $logger->unlike(qr/fatal/');
    $logger->count() == 3;
    $logger->clear();

    # Or simply see the messages
    diag($_) foreach @{ $logger->messages() };

# DESCRIPTION

`Test::Log::Abstraction` is a test double for [Log::Abstraction](https://metacpan.org/pod/Log%3A%3AAbstraction), drop-in wherever code under test is passed a `logger =>` object.

Every level method that `Log::Abstraction` offers (`trace`, `debug`, `info`, `notice`, `warn`, `error`, `critical`, `alert`, `emergency` and their syslog aliases) records the message instead of writing it to a file, and optionally sends it to TAP diagnostics. Nothing is ever written to disk, and no logging backend is loaded.

Messages at `warning` and above are printed with [Test::Builder/diag](https://metacpan.org/pod/Test%3A%3ABuilder) by default; `trace`, `debug`, `info` and `notice` are printed only in verbose mode (`verbose => 1` or `$ENV{TEST_VERBOSE}`). Change it with the `diag` option: `'all'`, `'none'`, a level name (threshold), or an array reference of levels.

## Migrating from t/lib/MyLogger.pm

Replace, in each test file:

    use lib 't/lib';
    use MyLogger;
    ...
    logger => MyLogger->new()

with:

    use Test::Log::Abstraction;
    ...
    logger => Test::Log::Abstraction->new()

and delete `t/lib/MyLogger.pm`.

# AUTHOR

Nigel Horne `<njh@nigelhorne.com>`
