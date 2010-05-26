use inc::Module::Install;
name 'shirokaned';
all_from 'lib/Shirokaned.pm';

requires 'Twiggy';
requires 'AnyEvent';
requires 'Mouse';
requires 'MouseX::Getopt';
requires 'FindBin::libs';
requires 'KyotoCabinet';
test_requires 'Test::TCP';

readme_markdown_from 'shirokaned';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More';
test_requires 'YAML';
author_tests('xt');
# use_test_base;
auto_include;
WriteAll;
