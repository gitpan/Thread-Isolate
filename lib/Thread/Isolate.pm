#############################################################################
## Name:        Isolate.pm
## Purpose:     Thread::Isolate
## Author:      Graciliano M. P. 
## Modified by:
## Created:     2005-01-29
## RCS-ID:      
## Copyright:   (c) 2005 Graciliano M. P. 
## Licence:     This program is free software; you can redistribute it and/or
##              modify it under the same terms as Perl itself
#############################################################################

package Thread::Isolate ;
use 5.008003 ;

use strict qw(vars);

use vars qw($VERSION @ISA) ;

$VERSION = '0.02' ;

@ISA = qw(Thread::Isolate::Thread) ;

###########
# REQUIRE #
###########

  use Storable () ;
  use Thread::Isolate::Thread ;
  
  Thread::Isolate::Thread::start_mother_thread() ;

######################
# STORABLE SIGNATURE #
######################

use vars qw($STORABLE_SIGN $NO_EXTERNAL_PERL) ;

BEGIN {
  if ( $STORABLE_SIGN eq '' ) {
    if ($NO_EXTERNAL_PERL) {
      $STORABLE_SIGN = unpack( 'l',Storable::freeze( [] )) ;
      $NO_EXTERNAL_PERL = 'Signature obtained locally' ;
    }
    else {
      open( my $handle,
      qq($^X -MStorable -e "print unpack('l',Storable::freeze( [] ))" | )
      ) or die "Cannot determine Storable signature\n" ;
      $STORABLE_SIGN = <$handle>;
    }
  }
}

##########
# FREEZE #
##########

sub freeze {
  if (@_) {
    foreach (@_) {
      return Storable::freeze( \@_ ) if !defined() or ref() or m#\0#;
    }
    return join( "\0",@_ );
  }
  else { return ;}
}

########
# THAW #
########

sub thaw {
  return unless defined( $_[0] ) and defined( wantarray );

  if (wantarray) {
    return @{Storable::thaw( $_[0] )} if (unpack( 'l',$_[0] )||0) == $STORABLE_SIGN ;
    split( "\0",$_[0] )
  }
  elsif ((unpack( 'l',$_[0] )||0) == $STORABLE_SIGN) {
    Storable::thaw( $_[0] )->[0];
  }
  else {
    return $1 if $_[0] =~ m#^([^\0]*)#;
    $_[0];
  }
}

#######
# END #
#######

1;


__END__

=head1 NAME

Thread::Isolate - Create Threads that can be called externally and use them to isolate modules from the main thread.

=head1 DESCRIPTION

This module has the main purpose to isolate loaded modules from the main thread.

The idea is to create the I<Thread::Isolate> object and call methods, evaluate
codes and use modules inside it, with synchronized and unsynchronized calls.

Also you can have multiple Thread::Isolate objects, with different states of the
Perl interpreter (different loaded modules in each thread).

To save memory Thread::Isolate holds a cleaner version of the Perl interpreter
when it's loaded, than it uses this Mother Thread to create all the other Thread::Isolate
objects.

=head1 USAGE

Synchronized calls:

  ## Load it soon as possible to save memory:
  use Thread::Isolate ;
  
  my $thi = Thread::Isolate->new() ;

  $thi->eval(' 2**10 ') ;
  
  ...
  
  $thi->eval(q`
    sub TEST {
      my ( $var ) = @_ ;
      return $var ** 10 ;
    }
  `) ;
  
  print $thi->call('TEST' , 2) ;

  ...
  
  $thi->use('Data::Dumper') ;
  
  print $thi->call('Data::Dumper::Dumper' , [123 , 456 , 789]) ;
  
Here's an example of an unsynchronized call (detached):

  my $job = $thi->eval_detached(q`
    for(1..5) {
      print "in> $_\n" ;
      sleep(1);
    }
    return 2**3 ;
  `);
  
  $job->wait_to_start ;

  while( $job->is_running ) {
    print "." ;
  }
  
  print $job->returned ;

=head1 Creating a copy of an already existent Thread::Isolate:

  my $thi = Thread::Isolate->new() ;
  
  ## Creates a thread inside/from $thi and return it:
  $thi2 = $thi->new_internal ;

The code above can be used to make different copies of different states of the
Perl Interpreter.

=head1 Thread::Isolate METHODS

=head2 new (%OPTIONS)

Create a new Thread::Isolate object.

From version 0.02 each new Thread::Isolate object will be a copy of a Mother
Thread that holds a cleaner state of the Perl interpreter.

B<OPTIONS:>

=over 4

=item no_mother_thread

Do not use default Mother Thread as generator of the new thread.
This will create a thread usign the current Perl thread. (Normal behavior of Perl threads).

=item mother_thread

A thread to be used as the generator of the new Thread::Isolate object.

=back

=head2 new_internal

Create a new Thread::Isolate inside the current Thread::Isolate object.

This can be used to copy/clone threads from external calls.

=head2 new_from_id (ID)

Returns an already created Thread::Isolate object using the ID.

=head2 clone

Return a cloned object. (This won't create a new Perl thread, is just a clone of the object reference).

=head2 copy

Create a copy of the thread. (Same as I<new_internal()>. Will create a new Perl thread).

=head2 use (MODULE , ARGS)

call I<'use MODULE qw(ARGS)'> inside the thread,

=head2 eval (CODE , ARGS)

Evaluate a CODE and paste ARGS inside the thread.

=head2 eval_detached (CODE , ARGS)

Evaluate detached (unsynchronous) a CODE and paste ARGS inside the thread.

Returns a I<Thread::Isolate::Job> object.

=head2 call (FUNCTION , ARGS)

call FUNCTION inside the thread.

=head2 call_detached (FUNCTION , ARGS)

call detached (unsynchronous) FUNCTION inside the thread.

Returns a I<Thread::Isolate::Job> object.

=head2 shutdown

Shutdown the thread.

=head2 exists

Return TRUE if the thread exists.

=head2 is_running_any_job

Return TRUE if the thread is running some job.

=head1 Thread::Isolate::Job METHODS

When a deteched method is called a job is returned.
Here are the methods to use the job object:

=head2 is_started

Return TRUE if the job was started.

=head2 is_running 

Return TRUE if the job is running.

=head2 is_finished  

Return TRUE if the job was finished.

=head2 wait_to_start  

Wait until the job starts. (Ensure that the job was started).

=head2 wait  

Wait until the job is finished. (Ensure that the job was fully executed).

Returns the arguments returneds by the job.

=head2 wait_to_finish  

Same as I<wait()>.

Wait until the job is finished. (Ensure that the job was fully executed).

Returns the arguments returneds by the job.

=head2 returned

Returns the arguments returneds by the job. It will wait the job to finish too.

=head1 SEE ALSO

L<Thread::Tie::Thread>, L<threads::shared>.

L<Safe::World>.

=head1 AUTHOR

Graciliano M. P. <gmpassos@cpan.org>

I will appreciate any type of feedback (include your opinions and/or suggestions). ;-P

This module was inspirated on L<Thread::Tie::Thread> by Elizabeth Mattijsen, <liz at dijkmat.nl>, the mistress of threads. ;-P

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

