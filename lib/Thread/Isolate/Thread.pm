#############################################################################
## Name:        Thread.pm
## Purpose:     Thread::Isolate::Thread
## Author:      Graciliano M. P. 
## Modified by:
## Created:     2005-01-29
## RCS-ID:      
## Copyright:   (c) 2005 Graciliano M. P. 
## Licence:     This program is free software; you can redistribute it and/or
##              modify it under the same terms as Perl itself
#############################################################################

package Thread::Isolate::Thread::EVAL ;

sub job_EVAL {
  package main ;
  no warnings ;
  local( $SIG{__WARN__} ) = sub {} ;
  local($_) = $#_ >= 2 ? [@_[2..$#_]] : [] ;
  return eval('package main ; @_ = @$_ ; $_ = "" ; ' . "\n#line 1\n" . $_[1]) ;
}

###########################
# THREAD::ISOLATE::THREAD #
###########################

package Thread::Isolate::Thread ;
use 5.008003 ;

use strict qw(vars);

###########
# REQUIRE #
###########

  use threads ;
  use threads::shared ;
  use Thread::Isolate::Job ;

########
# VARS #
########

  my ( $sub_THREAD_ISOLATE ) ;
  
  my $THI_ID : shared ;
  
  use vars qw($MOTHER_THREAD %THI_SHARE_TABLE %THI_THREAD_TABLE) ;
  
  share(%THI_SHARE_TABLE) ;
  $THI_SHARE_TABLE{id} = share_new_ref('%') ;
  $THI_SHARE_TABLE{tid} = share_new_ref('%') ;
  $THI_SHARE_TABLE{thread} = share_new_ref('%') ;
  $THI_SHARE_TABLE{creator} = share_new_ref('%') ;

#######################
# START_MOTHER_THREAD #
#######################

sub start_mother_thread {
  return if $MOTHER_THREAD ;
  
  my $thim = Thread::Isolate->new() ;
  $thim->{clone} = 1 ;
  
  $MOTHER_THREAD = $thim->id ;
}

#######
# NEW #
#######

sub new {
  my $this = shift ;
  return( $this ) if ref($this) ;
  my $class = $this || __PACKAGE__ ;
  
  if ( $#_ <= 1 && $_[0] =~ /^\d+$/ ) {
    return $class->new_from_id($_[0]) ;
  }
  
  my ($internal_level , %args) ;
  
  if ( caller eq __PACKAGE__ ) {
    if ( !( $#_ == 1 && !defined $_[0] && $_[1] ) && Thread::Isolate->self ) {
      die("Can't create an internal Thread::Isolate with an internal call to new()! Please call \$THI->new_internal() and use the returned id.\n") ;
      return ;
    }
    
    $internal_level = $_[1] * 1 ;
  }
  elsif ( @_ ) { %args = @_ ;}
  
  my $mother_thread = $args{mother_thread} || $MOTHER_THREAD ;
  
  $mother_thread = $mother_thread->{id} if ref($mother_thread) && UNIVERSAL::isa($mother_thread , 'Thread::Isolate') ;
  
  if ( $mother_thread && !$args{no_mother_thread} && !defined $internal_level ) {
    my $thim = Thread::Isolate->new_from_id($MOTHER_THREAD) ;
    return $thim->new_internal ;
  }
  
  $this = bless(share_new_ref('%') , $class) ;
  
  $this->{jobs} = share_new_ref('@') ;
  $this->{job_id} = share_new_ref('$') ;
  $this->{job_now} = share_new_ref('$') ;
  $this->{status} = share_new_ref('$') ;
  $this->{err} = share_new_ref('$') ;
  
  $this->{id} = ++$THI_ID ;
  
  my $shares = share_new_ref('@') ;

  $THI_SHARE_TABLE{ $this->{id} } = $shares ;
  
  $this->{internal_level} = $internal_level + 1 ;
  
  my $sub_thread = 'THREAD_ISOLATE' . $this->{internal_level} ;
  
  if ( !defined &$sub_thread ) {
    *{$sub_thread} = eval($sub_THREAD_ISOLATE) ;
  }
  
  ##print "START THREAD> $this->{id}\n" ;
  
  @$shares = %$this ;
  
  my $thread = threads->new( \&{$sub_thread} , $this ) ;
  
  $this->{tid} = $thread->tid ;
  
  $THI_SHARE_TABLE{id}{$this->{tid}} = $this->{id} ;
  $THI_SHARE_TABLE{tid}{$this->{id}} = $this->{tid} ;
  $THI_SHARE_TABLE{creator}{$this->{id}} = threads->self->tid ;
  
  $THI_THREAD_TABLE{ $this->{tid} } = $thread ;
  
  ## hold tid:
  @$shares = %$this ;

  threads->yield while !defined ${ $this->{status} } ;
  
  return $this ;
}

#################
# SHARE_NEW_REF #
#################

sub share_new_ref {
  if ( $_[0] eq '$' ) {
    my $tmp_ref = eval('my $tmp ; \$tmp') ;
    return share($$tmp_ref) ;
  }
  elsif ( $_[0] eq '@' ) {
    my $tmp_ref = [] ;
    return share(@$tmp_ref) ;
  }
  elsif ( $_[0] eq '%' ) {
    my $tmp_ref = {} ;
    return share(%$tmp_ref) ;
  }
}

#########
# CLONE #
#########

sub clone {
  my $this = shift ;
  return $this->new_from_id( $this->{id} ) ;
}

###############
# NEW_FROM_ID #
###############

sub new_from_id {
  my $this = UNIVERSAL::isa($_[0] , 'Thread::Isolate::Thread') ? shift(@_) : undef ;
  my $id = shift ;
  my $no_clone = shift ;
  
  return if !$THI_SHARE_TABLE{$id} || ref $THI_SHARE_TABLE{$id} ne 'ARRAY' ;
  
  my $shares = share_new_ref('%') ;
  
  %$shares = @{ $THI_SHARE_TABLE{$id} } ;
  $$shares{clone} = 1 if !$no_clone ;
  
  my $class = ref($this) || $this || __PACKAGE__ ;
  
  my $new = bless($shares , $class) ;
    
  return $new ;
}

################
# NEW_INTERNAL #
################

sub new_internal {
  my $this = shift ;
  my $thi_id = $this->run_job('NEW_INTERNAL' , $this->{internal_level}) ;
  
  my $new_int = ref($this)->new_from_id($thi_id) ;
  
  $new_int->{internal_level} = $this->{internal_level} + 1 ;
  
  return $new_int ;
}

sub copy { &new_internal ;}

########
# SELF #
########

sub self {
  my $id = $THI_SHARE_TABLE{id}{ threads->self->tid } ;
  return if !$id ;
  return new_from_id($_[0],$id) ;
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

######
# ID #
######

sub id {
  my $this = shift ;
  return $this->{id} ;
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
  
  {
    $the_job = Thread::Isolate::Job->new( $this , $job_type , @_ ) ;
    
    ##print "ADD>> ". $the_job->dump ."\n" ;
  
    lock( @$jobs ) ;
    
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
    
    while( !cond_timedwait( @$the_job , time+2 ) ) {
      last if $$the_job[2] >= 1 || ${$this->{status}} <= 0 ;
    }
  }
  
  threads->yield while $$the_job[2] < 1 && ${$this->{status}} > 0 ;
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

    return Thread::Isolate::thaw( $$the_job[4] ) if $$the_job[2] == 2 ;

    while( !cond_timedwait( @$the_job , time+2 ) ) {
      last if $$the_job[2] == 2 || ${$this->{status}} <= 0 ;
    }
  }
  
  threads->yield while $$the_job[2] != 2 && ${$this->{status}} > 0 ;
  return Thread::Isolate::thaw( $$the_job[4] ) ;
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
  
  if ( @_ ) {
    $this->run_job('EVAL', (wantarray? 1 : 0) , "use $module qw\0". join(" ", @_) ."\0 ;") ;
  }
  else {
    $this->run_job('EVAL', (wantarray? 1 : 0) , "use $module ;") ;
  }
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
  my $tid = $this->tid ;
  
  my $thread ;
  if ( $tid ) {
    $thread = $THI_THREAD_TABLE{$tid} || threads->object( $tid ) ;
  }

  $this->add_job('SHUTDOWN') ;

  $thread->join if UNIVERSAL::isa($thread , 'threads') ;

  $thread = undef ;

  return 1 ;
}

########
# KILL #
########

sub kill {
  my $this = shift ;
  
  my ($status) = @$this{qw(status)} ;
  
  { lock( $$status ) ;
    $$status = -1 ;
  }

  $this->shutdown if !$this->{clone} ;
}

############
# JOB_LIST #
############

sub job_list {
  my $this = shift ;
  
  my ($jobs) = @$this{qw(jobs)} ;
  
  my @list ;
  { lock( @$jobs ) ;
    push(@list , @$jobs) ;
  }
  
  return @list ;
}

###########
# DESTROY #
###########

sub DESTROY {
  my $this = shift ;
  return if $this->{clone} ;
  
  $this->shutdown if $this->tid != threads->self->tid && $this->exists ;
  
  delete $THI_SHARE_TABLE{ $this->{id} } ;
  
  %$this = () ;
  
  return 1 ;
}

##################
# THREAD_ISOLATE #
##################

$sub_THREAD_ISOLATE = q`
sub {
  my $this = shift ;
  
  $this->{tid} = threads->self->tid ;
  $THI_SHARE_TABLE{id}{$this->{tid}} = $this->{id} ;
  $THI_SHARE_TABLE{tid}{$this->{id}} = $this->{tid} ;
  
  ##warn "NEW THR>> $this->{id}\n" ;
  
  my ($jobs , $status) = @$this{qw(jobs status)} ;
  
  $$status = 1 ;
  
  my $running = 1 ;
  
  while( $running && $$status > 0 ) {
    lock( @$jobs ) ;

    #cond_wait( @$jobs ) if !@$jobs ;
    cond_timedwait( @$jobs , time + 2 ) if !@$jobs ;
    
    last if $$status <= 0 ;

    ##print threads->self->tid . "> RUN> $this->{id} [$MOTHER_THREAD]\n" ;
    
    my $the_job = pop(@$jobs) ;
  
    next if !defined $the_job ;
    
    ##print $the_job->dump ;
    
    $this->process_job($the_job , \$running) ;
  }
  
  @{$THI_SHARE_TABLE{ $this->{id} }} = () ;
  delete $THI_SHARE_TABLE{ $this->{id} } ;
  
  ##print "END> $this->{id} [$running , $$status]\n" ;
  
  $$status = 0 ;
  
  return ;
}

`; 

###############
# PROCESS_JOB #
###############

sub process_job {
  my $this = shift ;
  my $the_job = shift ;
  my $running = shift ;

  my ($jobs , $job_now , $err) = @$this{qw(jobs job_now err)} ;
  
  return if !defined $the_job ;
  
  $$the_job[2] = 1 ;
  $$job_now = $the_job ;
  
  my $job_type = $$the_job[3] ;
  my @args = Thread::Isolate::thaw( $$the_job[4] ) ;
  
  ##print $the_job->dump ;
  
  { lock( $$err ) ;
    
    if ($job_type eq 'SHUTDOWN') {
      @$jobs = () ;
      $$running = 0 if $running ;
    }
    elsif ($job_type eq 'EVAL') {
      my @ret ;
      if ( $args[0] ) { @ret = Thread::Isolate::Thread::EVAL::job_EVAL(@args) ;}
      else            { $ret[0] = Thread::Isolate::Thread::EVAL::job_EVAL(@args) ;}
      $$err = $@ ;
      $$the_job[4] = Thread::Isolate::freeze(@ret) ;
    }
    elsif ($job_type eq 'CALL') {
      my @ret ;
       eval {
        if ( $args[0] ) { @ret = job_CALL(@args) ;}
        else            { $ret[0] = job_CALL(@args) ;}
      };
      $$err = $@ ;
      $$the_job[4] = Thread::Isolate::freeze(@ret) ;
    }
    elsif ($job_type eq 'NEW_INTERNAL') {
      my $thi ;
      eval {
        $thi = Thread::Isolate->new( undef , $args[0] ) ;
      };
      $$err = $@ ;
      $$the_job[4] = Thread::Isolate::freeze( $thi->{id} ) ;
      $thi->{clone} = 1 ;
    }
    elsif ($job_type eq 'END') {
      $$running = 0 if $running ;
    }
  }
  
  { lock( @$the_job ) ;
    $$the_job[2] = 2 ;
    $$job_now = undef ;
    cond_signal( @$the_job ) ;
  }

}

############
# JOB_CALL #
############

sub job_CALL {
  package main ;
  return &{$_[1]}(@_[2..$#_]) ;
}

#######
# END #
#######

sub END {

  if ( $MOTHER_THREAD ) {
    my $thim = Thread::Isolate->new_from_id($MOTHER_THREAD) ;
    $thim->shutdown if $thim && $thim->exists ;
    $MOTHER_THREAD = undef ;  
  }

  my $tid = threads->self->tid ;

  foreach my $Key (sort keys %THI_SHARE_TABLE ) {
    my $thi = new_from_id($Key) ;
    $thi->shutdown if $thi && $thi->exists ;
  }

  %THI_SHARE_TABLE = () ;
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

