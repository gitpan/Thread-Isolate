#############################################################################
## Name:        Closed.pm
## Purpose:     Thread::Isolate
## Author:      Graciliano M. P. 
## Modified by:
## Created:     2005-01-29
## RCS-ID:      
## Copyright:   (c) 2005 Graciliano M. P. 
## Licence:     This program is free software; you can redistribute it and/or
##              modify it under the same terms as Perl itself
#############################################################################

package Thread::Isolate::EVAL ;

sub job_EVAL {
  package main ;
  no warnings ;
  local( $SIG{__WARN__} ) = sub {} ;
  local($_) = $#_ >= 2 ? [@_[2..$#_]] : [] ;
  return eval('package main ; @_ = @$_ ; $_ = "" ; ' . "\n#line 1\n" . $_[1]) ;
}

package Thread::Isolate ;
use 5.008 ;

use strict qw(vars);

use vars qw($VERSION @ISA) ;

$VERSION = '0.01' ;

###########
# REQUIRE #
###########

  use threads ;
  use threads::shared ;
  use Storable () ;

######################
# STORABLE SIGNATURE #
######################

use vars qw($STORABLE_SIGN $NO_EXTERNAL_PERL) ;

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

########
# VARS #
########

  my ( $THI_ID , %THI_SHARE_TABLE ) ;

#######
# NEW #
#######

sub new {
  my $this = shift ;
  return( $this ) if ref($this) ;
  my $class = $this || __PACKAGE__ ;

  $this = bless({} , $class) ;
  
  my @jobs : shared ;
  my $job_id : shared ;
  my $job_now : shared ;
  my $status : shared ;
  my $err : shared ;
  
  $this->{jobs} = \@jobs ;
  $this->{job_id} = \$job_id ;
  $this->{job_now} = \$job_now ;
  $this->{status} = \$status ;
  $this->{err} = \$err ;
  
  $this->{id} = ++$THI_ID ;
  
  $THI_SHARE_TABLE{ $this->{id} } = [ %$this ] ;
  
  $this->{tid} = threads->new( \&THREAD_ISOLATE , $this )->tid ;
  
  threads->yield while !defined $status ;

  return $this ;
}

##########
# EXISTS #
##########

sub exists {
  my $this = shift ;
  return if !threads->object( $this->tid ) ;
  
  my ($status) = @$this{qw(status)} ;
  
  my $exists ;
  
  { lock( $$status ) ;
    $exists = 1 if $$status ;
  }
  
  $status = undef ;
  
  return $exists ;
}

#######
# ERR #
#######

sub err {
  my $this = shift ;
  
  my $err ;
  
  { lock( ${$this->{err}} ) ;
    $err = ${$this->{err}} ;
  }
  
  return $err ;
}

#######
# TID #
#######

sub tid {
  my $this = shift ;
  return $this->{tid} ;
}

######################
# IS_RUNNING_ANY_JOB #
######################

sub is_running_any_job {
  my $this = shift ;
  my ($job_now) = @$this{qw(job_now)} ;
  {
    lock( $$job_now ) ;
    return 1 if defined $$job_now ;
  }
  return ;
}

##################
# IS_JOB_STARTED #
##################

sub is_job_started {
  my $this = shift ;
  my ( $the_job ) = @_ ;
  return if !UNIVERSAL::isa($the_job , 'Thread::Isolate::Job') ;
  
  {
    lock( @$the_job ) ;
    return 1 if $$the_job[2] >= 1 ;
  }
  
  return ;
}

##################
# IS_JOB_RUNNING #
##################

sub is_job_running {
  my $this = shift ;
  my ( $the_job ) = @_ ;
  return if !UNIVERSAL::isa($the_job , 'Thread::Isolate::Job') ;
  
  {
    lock( @$the_job ) ;
    return 1 if $$the_job[2] == 1 ;
  }
  
  return ;
}

###################
# IS_JOB_FINISHED #
###################

sub is_job_finished {
  my $this = shift ;
  my ( $the_job ) = @_ ;
  return if !UNIVERSAL::isa($the_job , 'Thread::Isolate::Job') ;
  
  {
    lock( @$the_job ) ;
    return 1 if $$the_job[2] == 2 ;
  }
  
  return ;
}

###########
# ADD_JOB #
###########

sub add_job {
  my $this = shift ;
  my $job_type = shift ;
  
  my ($jobs , $status) = @$this{qw(jobs status)} ;
  
  my $the_job ;
  
  { lock( @$jobs ) ;

    $the_job = Thread::Isolate::Job->new( $this , $job_type , @_ ) ;
    
    push(@$jobs , $the_job) ;
    
    cond_signal( @$jobs ) ;
  }
  
  return $the_job ;
}

#####################
# WAIT_JOB_TO_START #
#####################

sub wait_job_to_start {
  my $this = shift ;
  my ( $the_job ) = @_ ;
  return if !UNIVERSAL::isa($the_job , 'Thread::Isolate::Job') ;
  
  {
    lock( @$the_job ) ;
    return 1 if $$the_job[2] >= 1 ;
    cond_wait( @$the_job ) ;
  }
  
  threads->yield while $$the_job[2] < 1 ;
  return 1 ;
}

############
# WAIT_JOB #
############

sub wait_job {
  my $this = shift ;
  my ( $the_job ) = @_ ;
  return if !UNIVERSAL::isa($the_job , 'Thread::Isolate::Job') ;
  
  {
    lock( @$the_job ) ;
    return thaw( $$the_job[4] ) if $$the_job[2] == 2 ;
    cond_wait( @$the_job ) ;
  }
  
  threads->yield while $$the_job[2] != 2 ;
  return thaw( $$the_job[4] ) ;
}

sub wait_job_to_finish { &wait_job ;}
sub job_returned { &wait_job ;}

###########
# RUN_JOB #
###########

sub run_job {
  my $this = shift ;
  my $job = $this->add_job(@_) ;
  $this->wait_job($job) ;
}

#######
# USE #
#######

sub use {
  my $this = shift ;
  my $module = shift ;
  $this->run_job('EVAL', (wantarray? 1 : 0) , "use $module qw\0". join(" ", @_) ."\0 ;") ;
}

########
# CALL #
########

sub call_detached {
  my $this = shift ;
  return $this->add_job('CALL', (wantarray? 1 : 0) , @_) ;
}

sub call {
  my $this = shift ;
  $this->wait_job( $this->call_detached(@_) ) ;
}

########
# EVAL #
########

sub eval_detached {
  my $this = shift ;
  return $this->add_job('EVAL', (wantarray? 1 : 0) , @_) ;
}

sub eval {
  my $this = shift ;
  $this->wait_job( $this->eval_detached(@_) ) ;
}

############
# SHUTDOWN #
############

sub shutdown {
  my $this = shift ;
  
  my $thread = threads->object( $this->tid ) ;

  $this->add_job('SHUTDOWN') ;
  $thread->join if UNIVERSAL::isa($thread , 'threads') ;
  
  $thread = undef ;
  
  return 1 ;
}

###########
# DESTROY #
###########

sub DESTROY {
  my $this = shift ;
  return if $this->{clone} ;
  
  $this->shutdown ;
  
  delete $THI_SHARE_TABLE{ $this->{id} } ;
  
  return 1 ;
}

##################
# THREAD_ISOLATE #
##################

sub THREAD_ISOLATE {
  my $this = shift ;
  
  my ($jobs , $job_now , $status , $err) = @$this{qw(jobs job_now status err)} ;
  
  $$status = 1 ;
  
  my $running = 1 ;
  
  while($running) {
    lock( @$jobs ) ;
    cond_wait( @$jobs ) if !@$jobs ;
    
    my $the_job = pop(@$jobs) ;
    
    next if !defined $the_job ;
    
    $$the_job[2] = 1 ;
    $$job_now = $the_job ;
    
    my $job_type = $$the_job[3] ;
    my @args = thaw( $$the_job[4] ) ;
    
    ##print "THC> $job_type [@args]\n" ;
    
    lock( $$err ) ;
    
    if ($job_type eq 'SHUTDOWN') {
      @$jobs = () ;
      $running = 0 ;
    }
    elsif ($job_type eq 'EVAL') {
      my @ret ;
      if ( $args[0] ) { @ret = Thread::Isolate::EVAL::job_EVAL(@args) ;}
      else            { $ret[0] = Thread::Isolate::EVAL::job_EVAL(@args) ;}
      $$err = $@ ;
      $$the_job[4] = freeze(@ret) ;
    }
    elsif ($job_type eq 'CALL') {
      my @ret ;
       eval {
        if ( $args[0] ) { @ret = job_CALL(@args) ;}
        else            { $ret[0] = job_CALL(@args) ;}
      };
      $$err = $@ ;
      $$the_job[4] = freeze(@ret) ;
    }
    
    lock( @$the_job ) ;
    $$the_job[2] = 2 ;
    cond_signal( @$the_job ) ;
    
    $$job_now = undef ;
  }
  
  $$status = 0 ;
  
  return ;
}

############
# JOB_CALL #
############

sub job_CALL {
  package main ;
  return &{$_[1]}(@_[2..$#_]) ;
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

########################
# THREAD::ISOLATE::JOB #
########################

package Thread::Isolate::Job ;

#######
# NEW #
#######

sub new {
  my $this = shift ;
  return( $this ) if ref($this) ;
  my $class = $this || __PACKAGE__ ;

  my $thi = shift ;
  my $job_type = shift ;

  my @the_job : shared ;

  $this = bless(\@the_job , $class) ;
  
  my $id = ++${$thi->{job_id}} ;
  
  @the_job = ( $thi->{id} , $id , undef , $job_type , Thread::Isolate::freeze(@_) ) ;

  return $this ;
}

############
# _THI_OBJ #
############

sub _thi_obj {
  my $this = shift ;
  my %shares = @{ $THI_SHARE_TABLE{ $$this[0] } } ;
  
  $shares{clone} = 1 ;
  
  return bless \%shares , 'Thread::Isolate' ;
}

###########
# ALIASES #
###########

sub is_started {
  my $this = shift ;
  $this->_thi_obj->is_job_started($this) ;
}

sub is_running {
  my $this = shift ;
  $this->_thi_obj->is_job_running($this) ;
}

sub is_finished {
  my $this = shift ;
  $this->_thi_obj->is_job_finished($this) ;
}

sub wait_to_start {
  my $this = shift ;
  $this->_thi_obj->wait_job_to_start($this) ;
}

sub wait {
  my $this = shift ;
  $this->_thi_obj->wait_job($this) ;
}

sub wait_to_finish {
  my $this = shift ;
  $this->_thi_obj->wait_job($this) ;
}

sub returned {
  my $this = shift ;
  $this->_thi_obj->wait_job($this) ;
}

###########
# DESTROY #
###########

sub DESTROY {
  my $this = shift ;
  
  { lock( @$this ) ;
    if ( !$$this[2] && $$this[3] ne 'SHUTDOWN' ) {
      $$this[2] = 2 ;
      $$this[4] = '' ;
    }
  }

  return ;
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

=head1 USAGE

Synchronized calls:

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

=head1 Thread::Isolate METHODS

=head2 new

Create a new Thread::Isolate object.

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

