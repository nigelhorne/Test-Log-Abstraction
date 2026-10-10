use strict;
use warnings;
use ExtUtils::MakeMaker;

my $dist = {
	COMPRESS => 'gzip -9f',	# Compress tarball using gzip
	SUFFIX => 'gz',	# File suffix for tarball
};

if($^O eq 'darwin') {
	$dist->{'TAR'} = 'gtar';
}

WriteMakefile(
	NAME => 'Test::Log::Abstraction',
	VERSION_FROM => 'lib/Test/Log/Abstraction.pm',
	ABSTRACT_FROM => 'lib/Test/Log/Abstraction.pm',
	AUTHOR => 'Nigel Horne <njh@nigelhorne.com>',
	LICENSE => 'GPL',
	MIN_PERL_VERSION => '5.014',	# Sub::Private and Sub::Protected need 5.14
	PREREQ_PM => {
		'autodie' => 0,
		'Carp' => 0,
		'Encode' => 0,
		'IPC::System::Simple' => 0,	# autodie qw(:all)
		'Params::Get' => 0.17,
		'Params::Validate::Strict' => 0.41,	# union types
		'Readonly' => 0,
		'Scalar::Util' => 0,
		'Sub::Private' => 0.06,	# localisable enforce mode
		'Sub::Protected' => 0.03,
		'Test::Builder' => 0,
		'warnings' => 0,
		'strict' => 0,
	},
	TEST_REQUIRES => {
		'Errno' => 0,
		'Exporter' => 0,
		'Test::Builder::Tester' => 0,
		'Test::Most' => 0,
		'Test::Warnings' => 0,
	}, dist => $dist,
	clean	 => { FILES => 'Test-Log-Abstraction-*' },
	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources => {
			homepage => 'https://metacpan.org/pod/Test::Log::Abstraction',
			repository => {
				repository => 'https://github.com/nigelhorne/Test-Log-Abstraction',
				type => 'git',
				url => 'git://github.com/nigelhorne/Test-Log-Abstraction.git',
				web => 'https://github.com/nigelhorne/Test-Log-Abstraction',
			}, bugtracker => {
				mailto => 'bug-Test-Log-Abstraction@rt.cpan.org',
				web => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Test-Log-Abstraction',
				url => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Test-Log-Abstraction',
			}
		},
	},
);
