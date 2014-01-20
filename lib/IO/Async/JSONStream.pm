#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2014 -- leonerd@leonerd.org.uk

package IO::Async::JSONStream;

use strict;
use warnings;

our $VERSION = '0.01';

use base qw( IO::Async::Stream );
IO::Async::Stream->VERSION( '0.57' ); # ->read future

use JSON qw( encode_json decode_json );

use Carp;

=head1 NAME

C<IO::Async::JSONStream> - send or receive lines of JSON data in C<IO::Async>

=head1 SYNOPSIS

 use IO::Async::JSONStream;

 use IO::Async::Loop;
 my $loop = IO::Async::Loop->new;

 my $jsonstream = IO::Async::JSONStream->new;
 $loop->add( $jsonstream );

 $jsonstream->connect(
    host    => "my.server",
    service => 12345,
 )->then( sub {
    $jsonstream->write_json( [ data => { goes => "here" } ] );
    $jsonstream->read_json
 })->on_done( sub {
    my ( $data ) = @_;

    print "Received the data $data\n";
 })->get;

=head1 DESCRIPTION

This subclass of L<IO::Async::Stream> implements a simple JSON-encoded data
stream, sending and receiving Perl data structures by JSON-encoded lines of
text.

=cut

=head1 EVENTS

The following events are invoked, either using subclass methods or CODE
references in parameters:

=head2 on_json $data

Invoked when a line of JSON-encoded data is received. It is passed the decoded
data as a regular Perl data structure.

=head2 on_json_error $error, $line

Invoked when a line is received but JSON decoding fails. It is passed the
failure exception from the JSON decoder and the line on which decoding failed.

=cut

=head1 PARAMETERS

The following named parameters may be passed to C<new> or C<configure>:

=over 8

=item on_json => CODE

=item on_json_error => CODE

CODE references for event handlers.

=item eol => STRING

Optional. Sets the string used for the line ending on the stream. Defaults to
C<\n> if not given.

=back

=cut

sub _init
{
   my $self = shift;
   $self->SUPER::_init( @_ );

   $self->{eol} = "\n";
}

sub configure
{
   my $self = shift;
   my %args = @_;

   foreach (qw( on_json on_json_error eol )) {
      $self->{$_} = delete $args{$_} if exists $args{$_};
   }

   if( $self->read_handle ) {
      $self->can_event( $_ ) or croak "Expected either an $_ callback or to be able to ->$_"
         for qw( on_json on_json_error );
   }

   $self->SUPER::configure( %args );
}

sub on_read
{
   my $self = shift;
   my ( $buffref, $eof ) = @_;
   return if $eof;

   my $eol = $self->{eol};

   while( $$buffref =~ s/^(.*)\Q$eol// ) {
      my $line = $1;
      my $data;
      if( eval { $data = decode_json( $line ); 1 } ) {
         $self->invoke_event( on_json => $data );
      }
      else {
         chomp( my $e = $@ );
         $self->invoke_event( on_json_error => $e, $line );
      }
   }

   return 0;
}

=head1 METHODS

=cut

=head2 $jsonstream->write_json( $data, %args )

Writes a new line of JSON-encoded data from the given Perl data structure.

Other arguments are passed to the C<write> method. Returns a C<Future> which
will complete when the line is flushed.

=cut

sub write_json
{
   my $self = shift;
   my ( $data, @args ) = @_;

   $self->write( encode_json( $data ) . $self->{eol}, @args );
}

=head2 $jsonstream->read_json ==> $data

Returns a L<Future> that will yield the next line of JSON-encoded data to be
read from the stream. This takes place instead of the C<on_json> event.

If a JSON decoding error occurs it will result in a failed Future with the
operation name C<json> and the line on which decoding failed as its argument.

=cut

sub read_json
{
   my $self = shift;
   $self->read_until( $self->{eol} )->then( sub {
      my ( $line ) = @_;
      my $data;
      if( eval { $data = decode_json( $line ); 1 } ) {
         return Future->new->done( $data );
      }
      else {
         chomp( my $e = $@ );
         return Future->new->fail( $e, json => $line );
      }
   });
}

=head1 TODO

=over 2

=item *

Consider a true streaming mode, using C<JSON>'s incremental parsing ability.

=back

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
