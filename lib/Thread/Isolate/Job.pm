#############################################################################
## Name:        Job.pm
## Purpose:     Thread::Isolate::Job
## Author:      Graciliano M. P. 
## Modified by:
## Created:     2005-01-29
## RCS-ID:      
## Copyright:   (c) 2005 Graciliano M. P. 
## Licence:     This program is free software; you can redistribute it and/or
##              modify it under the same terms as Perl itself
#############################################################################

package Thread::Isolate::Job ;

use strict qw(vars) ;
no warnings ;

#######
# NEW #
#######

sub new {
  my $this = shift ;
  return( $this ) if ref($this) ;
  my $class = $this || __PACKAGE__ ;

  my $thi = shift ;
  my $job_type = shift ;

  my $the_job = Thread::Isolate::Thread::share_new_ref('@') ;

  $this = bless($the_job , $class) ;
  
  my ($job_id) = @$thi{qw(job_id)} ;
  
  my $id ;
  
  { lock( $$job_id ) ; 
    $id = ++$$job_id ;
  }
  
  @$the_job = ( $thi->{id} , $id , undef , $job_type , Thread::Isolate::freeze(@_) ) ;

  return $this ;
}

###############
# SET_NO_LOCK #
###############

sub set_no_lock {
  my $this = shift ;
  $$this[5] = 1 ;
}

#################
# UNSET_NO_LOCK #
#################

sub unset_no_lock {
  my $this = shift ;
  $$this[5] = 0 ;
}

##############
# IS_NO_LOCK #
##############

sub is_no_lock {
  my $this = shift ;
  return 1 if $$this[5] ;
  return ;
}

#########
# CLONE #
#########

sub clone {
  my $this = shift ;
  
  my $the_job = Thread::Isolate::Thread::share_new_ref('@') ;
  
  my $clone = bless($the_job , ref($this)) ;
  
  @$the_job = @$this ;
  
  return $clone ;
}

############
# _THI_OBJ #
############

sub _thi_obj {
  my $this = shift ;
  return Thread::Isolate::Thread::new_from_id( $$this[0] ) ;
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

########
# DUMP #
########

sub dump {
  my $this = shift ;
  my $dump ;
  
  my $tid = $$this[0] ;
  my $id = $$this[1] ;
  my $done = $$this[2] ;
  my $job_type = $$this[3] ;
  my @args = Thread::Isolate::thaw( $$this[4] ) ;
  
  $dump .= "JOB[$tid:$id][$done] TYPE[$job_type]" ;
  
  $dump .= " ARGS[". join (' ', @args) ."]" if @args ;
  
  $dump .= "\n" ;  
  
  return $dump ;
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


