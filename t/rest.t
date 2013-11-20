#!/usr/bin/perl

use strict;
use Test::More;
use Test::HTTP::Server;
use File::Temp;

use ShardedKV;
use ShardedKV::Continuum::Ketama;

BEGIN { use_ok( 'ShardedKV::Storage::Rest' ); }

my @test_urls;

my $orig_env = $ENV{HTTP_PORT};

my %hash = ();

my $tempdir = File::Temp->newdir();

$ENV{HTTP_PORT} = 1025 + rand()%64510;
my $server = Test::HTTP::Server->new( mem => \%hash);
$ENV{HTTP_PORT} = 1025 + rand()%64510;
my $server2 = Test::HTTP::Server->new(mem => \%hash);

$ENV{HTTP_PORT} = $orig_env;

push @test_urls, $server->uri."test";
push @test_urls, $server2->uri."test";


sub Test::HTTP::Server::Request::test
{
    my $self = shift;
    $self->{out_headers}->{'Content-Length'} = 0;
    my $path = $self->{request}->[1];
    my $key = (split('/', $path))[-1];
    my ($num) = $key =~ /test_key(\d+)/;
    if ($self->{request}->[0] eq 'PUT') {
        open OUT, ">$tempdir/$key";
        print OUT $self->{body};
        close OUT;
    } elsif ($self->{request}->[0] eq 'GET') {
        open IN, "$tempdir/$key";
        my $out;
        while(<IN>) {
            $out .= $_;
        }
        close(IN);
        if (defined $out) {
            $self->{out_headers}->{'Content-Length'} = length($out);
            return $out;
        }
    } elsif ($self->{request}->[0] eq 'DELETE') {
        $self->{out_headers}->{'Content-Length'} = 0;
        unlink "$tempdir/$key";
    }
    return "";
}


# Redis storage chosen here, but can also be "Memory" or "MySQL".
# "Memory" is for testing. Mixing storages likely has weird side effects.
my %storages;
my $continuum_spec;
foreach my $i (1..@test_urls) {
    my $shard = "shard$i";
    push(@$continuum_spec, ["shard$i", 100]);
    $storages{$shard} = ShardedKV::Storage::Rest->new(url => $test_urls[$i-1]);
}
my $continuum = ShardedKV::Continuum::Ketama->new(from => $continuum_spec);

my $skv = ShardedKV->new(
    storages => \%storages,
    continuum => $continuum,
);

my $key = "test_key";
my $value = "test_value";

my $num_items = 10;
foreach my $i (0..$num_items) {
    is ($skv->set("${key}$i", "${value}$i"), 1);
}
foreach my $i (0..$num_items) {
    my $stored_value = $skv->get("${key}$i");
    is($stored_value, "${value}$i");
    $skv->delete("${key}$i");
    is($skv->get("${key}$i"), undef);
}

done_testing();
