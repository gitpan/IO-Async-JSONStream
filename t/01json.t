#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;
use IO::Async::Test;
use IO::Async::Loop;
use JSON qw( encode_json decode_json );

use IO::Async::JSONStream;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $S1, $S2 ) = IO::Async::OS->socketpair() or die "Cannot create socketpair - $!";

my $jsonstream = IO::Async::JSONStream->new(
   write_handle => $S1,
);

ok( defined $jsonstream, 'defined $jsonstream' );

isa_ok( $jsonstream, "IO::Async::JSONStream", '$jsonstream' );
isa_ok( $jsonstream, "IO::Async::Stream", '$jsonstream' );

$loop->add( $jsonstream );

# write
{
   my $flushed;
   my $f = $jsonstream->write_json( [ "the", "data", "here", "café" ],
      on_flush => sub { $flushed++ },
   );

   my $stream = "";
   wait_for_stream { $stream =~ m/.*\n/ } $S2 => $stream;

   pass( 'Line written to test socket' );
   ok( $flushed, '->write_json takes on_flush argument' );

   like( $stream, qr/caf\xC3\xA9/, '$stream contains UTF-8 bytes' );

   is_deeply( decode_json( $stream ),
              [ "the", "data", "here", "café" ],
              'JSON-formatted line written' );

   ok( $f->is_ready, '->write_json returns Future that is ready' );
}

$jsonstream->configure(
   read_handle => $S1,
   on_json => sub {},
   on_json_error => sub {},
);

# read future
{
   my $f = $jsonstream->read_json;

   $S2->syswrite( encode_json( [ "data", "for", "future" ] ) . "\n" );

   wait_for { $f->is_ready };

   is_deeply( $f->get,
              [ "data", "for", "future" ],
              'JSON-formatted line received by Future' );
}

# read event
{
   my @data;
   $jsonstream->configure(
      on_json => sub { push @data, $_[1] },
   );

   $S2->syswrite( encode_json( [ "data", "for", "event" ] ) . "\n" );

   wait_for { @data };

   is_deeply( $data[0],
              [ "data", "for", "event" ],
              'JSON-formatted line received by event' );
}

# read errors future
{
   my $f = $jsonstream->read_json;

   $S2->syswrite( "this is not json\n" );

   wait_for { $f->is_ready };

   is( ( $f->failure )[1], "json", 'Non-JSON line yields "json" failure' );
}

# read errors event
{
   my ( $err, $errline );
   $jsonstream->configure(
      on_json_error => sub { $err++; $errline = $_[2] },
   );

   $S2->syswrite( "this is not json\n" );

   wait_for { $err };

   is( $errline, "this is not json", 'Non-JSON line invokes on_json_error with line' );
}

done_testing;
