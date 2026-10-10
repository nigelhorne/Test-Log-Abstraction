# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.014';

requires 'autodie';
requires 'Carp';
requires 'Encode';
requires 'IPC::System::Simple';
requires 'Params::Get', '0.17';
requires 'Params::Validate::Strict', '0.41';
requires 'Readonly';
requires 'Scalar::Util';
requires 'Sub::Private', '0.06';
requires 'Sub::Protected', '0.03';
requires 'Test::Builder';
requires 'strict';
requires 'warnings';

on 'test' => sub {
	requires 'Errno';
	requires 'Exporter';
	requires 'Test::Builder::Tester';
	requires 'Test::Memory::Cycle';
	requires 'Test::Mockingbird', '0.14';
	requires 'Test::Most';
	requires 'Test::Returns', '0.04';
	requires 'Test::Warnings';
};

on 'develop' => sub {
	requires 'Geo::IP';	# optional: t/locales.t GeoIP drift check
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
