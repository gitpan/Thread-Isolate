#########################

###use Data::Dumper ; print Dumper(  ) ;

use Test;
BEGIN { plan tests => 11 } ;

use Thread::Isolate ;

use strict ;
use warnings qw'all' ;

#########################
{
  ok(1) ;
}
#########################
{

  my $thi = Thread::Isolate->new() ;
  
  ok( $thi->eval(' 2**10 ')  , 1024 );

}
#########################
{

  my $thi = Thread::Isolate->new() ;
  
  $thi->eval(q`
    sub TEST {
      my ( $var ) = @_ ;
      return $var ** 10 ;
    }
  `) ;
  
  ok( $thi->call('TEST' , 2)  , 1024 );  
  ok( $thi->call('TEST' , 3)  , 59049 );  
  ok( $thi->call('TEST' , 4)  , 1048576 );

}
#########################
{

  my $thi = Thread::Isolate->new() ;
  
  $thi->use('Data::Dumper') ;
  
  ok( !$thi->err ) ;
  
  my $dump = $thi->call('Data::Dumper::Dumper' , [123 , 456 , 789]) ;
  
  $dump =~ s/\s+/ /gs ;
  
  ok($dump , '$VAR1 = [ 123, 456, 789 ]; ') ;

  ok( !$INC{'Data/Dumper.pm'} ) ;

}
#########################
{

  my $thi = Thread::Isolate->new() ;
  
  my $job = $thi->eval_detached(q`
    for(1..5) {
      print "in> $_\n" ;
      sleep(1);
    }
    return 2**3 ;
  `);
  
  $job->wait_to_start ;
  
  my $i ;
  while( $job->is_running ) {
    ++$i ;
    print "out> $i\n" ;
    sleep(1);
  }
  
  ok($i >= 2) ;
  
  ok( $job->returned , 8 ) ;
  
  $job = undef ;
  
  ok( $thi->exists ) ;

}
#########################

print "\nThe End! By!\n" ;

1 ;
