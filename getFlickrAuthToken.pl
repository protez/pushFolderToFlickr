#!/usr/bin/env perl
#
# getFlickrAuthToken.pl
#
# V1.0 - Sascha Schmidt (sascha@schmidt.ps)
#        http://blog.schmidt.ps
#

use strict;
use Flickr::API;

my $version = "1.0";

### MAIN ###
print "getFlickrAuthToken.pl - V$version\n\n"; 

print "1. Navigate to http://www.flickr.com/services/apps/create/apply to get your personal API key.\n\n";

print "2. Enter API-Key: ";
my $auth_key = <STDIN>;
chomp($auth_key);

print "3. Enter API-Secret-Key: ";
my $auth_secret = <STDIN>;
chomp($auth_secret);

# Initialize API module.
my $api = new Flickr::API({
   'key' => $auth_key,
   'secret' => $auth_secret,
   'unicode' => 1
});

my $response = $api->execute_method(
   'flickr.auth.getFrob', {
   'api_key' => $auth_key
});
if ( $response->{success} != 1 )
{
   print "ERROR: Could not auth against the flickr api!\n";
   print    "( ". $response->{error_message} ." )\n";
   exit -1;
} 

my $frob = $response->{tree}->{children}->[1]->{children}->[0]->{content};

print "4. Navigate to the following url and acknowledge the requested permissions.\n";
print "   ". $api->request_auth_url("delete", $frob) ."\n";
print "Hit <ENTER> when finished...";
<STDIN>;

$response = $api->execute_method(
   'flickr.auth.getToken', {
   'api_key' => $auth_key,
   'auth_secret' => $auth_secret,
   'frob' => $frob,
});
if ( $response->{success} != 1 )
{
   print "ERROR: Could not fetch auth token!\n";
   print    "( ". $response->{error_message} ." )\n";
   exit -1;
}
my $auth_token = $response->{tree}->{children}->[1]->{children}->[1]->{children}->[0]->{content};

print "\nFinished! This is your authdata:\n";
print "API-Key       : $auth_key\n";
print "API-Secret-Key: $auth_secret\n";
print "Auth-Token    : $auth_token\n\n";

print "You can use this perlcode within my scripts to configure the api auth:\n";
print "my \$auth_key = '$auth_key';\n";
print "my \$auth_secret = '$auth_secret';\n";
print "my \$auth_token = '$auth_token';\n";

