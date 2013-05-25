#!/usr/bin/env perl 
# 
# pushFolderToFlickr.pl 
# 
# V1.1 - Sascha Schmidt <sascha@schmidt.ps> 
#        http://blog.schmidt.ps
#

use strict; 
use Flickr::Upload; 
use Flickr::API 1.07;
use Data::Dumper;
use File::Basename;
use Encode;

# Flickr API authentication credentials. 
my $auth_key = '?';
my $auth_secret = '?';
my $auth_token = '?';

# Scriptname and version.
my $version = "1.1";
my $app_title = "Flickr::Upload::pushFolderToFlickr/$version";
my $tries = 10;
my $debug = 0;

### MAIN ###
if ( @ARGV == 0 )
{
   print "ERROR: No arguments given!\n";
   print "Syntax: ./pushFolderToFlickr.pl <directory> [-q]\n";
   exit -1;
}

my $quiet = 0;
if ( @ARGV[1] eq "-q" )
{
   $quiet = 1;
}

my $dir = @ARGV[0];
my $setname = basename($dir);
utf8::decode($setname);

# Initialize upload-module.
my $ua = Flickr::Upload->new({
   'key' => $auth_key,
   'secret' => $auth_secret
}); 
$ua->agent($app_title); 

# Initialize flickr-module.
my $api = new Flickr::API({
   'key' => $auth_key,
   'secret' => $auth_secret,
   'unicode' => 1
});
my $response = $api->execute_method(
   'flickr.people.getUploadStatus', {
   'api_key' => $auth_key,
   'auth_token' => $auth_token,
});
if ( $response->{success} != 1 )
{
   print "ERROR: Could not fetch upload status!\n";
   print    "( ". $response->{error_message} ." )\n";
   exit -1;
}

if ( $quiet == 0 ) { print "pushFolderToFlickr - V". $version ."\n\n"; }
if ( $quiet == 0 ) { print "Bandwidth summary:\n"; }
if ( $quiet == 0 ) { print "   Remaining KB: ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{remainingkb} ."\n"; }
if ( $quiet == 0 ) { print "   Used KB     : ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{usedkb} ."\n"; }
if ( $quiet == 0 ) { print "   Max KB      : ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{maxkb} ."\n\n"; }

upload_folder(); 

sub upload_folder() 
{
   my @photoids = ();        
   my $resp;
   my $loop;

   if (-d $dir) 
   {        
      opendir(DIR, $dir) || die "ERROR: Cannot open directory ". $dir .":". $!;                                                        
      print "Uploading images from directory: $dir\n";

      my $uploadcount = 0;
      foreach my $image (sort readdir(DIR)) 
      {
         my(undef, undef, $ext) = fileparse($image,qr{\..*});
         $ext = lc($ext);

         if ($image ne "." && $image ne ".." && ! -d $image &&
            ($ext eq ".jpg" || $ext eq ".png" || $ext eq ".gif") )
         {
            my $file = $dir ."/". $image; 

            $loop = 1;
            do
            {
               $resp = $ua->upload( 
                  'photo' => $file, 
                  'auth_token' => $auth_token, 
               );

               if (! $resp )
               {
                  print "ERROR: Failed to upload: $image (Try $loop)\n";
                  $loop++;
                  if ( $loop == $tries+1 ) { rollback($setname, "", @photoids); exit -1; } 
               } else
               {
                  if ( $quiet == 0 ) { print "Finished uploading: $image\n"; }
                  if ( $quiet == 1 )
                  {
                     if ( $loop > 1 )
                     {
                        print "Finished upload: $image (Try $loop)\n";
                     }
                  }
                  push(@photoids, $resp);
                  $uploadcount++;
                  $loop = 99;
               }
            } while ( $loop < $tries+1 );
         } 
      } 
      close(DIR); 

      if ( $uploadcount > 0 )
      {
         print "Upload finished for directory: $dir\n";
         addPicturesToPhotoset($setname, @photoids);
      }
   } 
   return; 
}

sub addPicturesToPhotoset()
{
   my ($setname, @photoids) = @_; 
   my $setid;
   my $response;

   my $loop = 1;
   do
   {
      $response = $api->execute_method(
         'flickr.photosets.create', {
         'api_key' => $auth_key,
         'auth_token' => $auth_token,
         'title' => $setname,
         'primary_photo_id' => @photoids[0] 
      });

      if ( $response->{success} != 1 )
      {
         print "ERROR: Could not create photoset! (Try $loop)\n";
         print    "( ". $response->{error_message} ." )\n";
         $loop++;
         if ( $loop == $tries+1 ) { rollback($setname, "", @photoids); exit -1; }
      } else
      {
         if ( $loop > 1 ) { print "Photoset created. (Try $loop)\n"; }
         $loop = 99;
      }
   } while ( $loop < $tries+1 );

   $setid = $response->{tree}->{children}->[1]->{attributes}->{id};

   foreach my $item (@photoids)
   {
      if ( $item != @photoids[0] )
      {
         $loop = 1;
         do
         { 
            $response = $api->execute_method(
               'flickr.photosets.addPhoto', {
               'api_key' => $auth_key,
               'auth_token' => $auth_token,
               'photoset_id' => $setid,
               'photo_id' => $item 
            });
            if ( $response->{success} != 1 )
            {
               print "ERROR: Could not add photo $item to photoset! (Try $loop)\n";
               print    "( ". $response->{error_message} ." )\n";
               $loop++;
               if ( $loop == $tries+1 ) { rollback($setname, $setid, @photoids); exit -1; }
            } else
            {
               if ( $loop > 1 ) { print "Added photo $item to photoset. (Try $loop)\n"; }
               $loop = 99;
            }
         } while ( $loop < $tries+1 );
      }
   }
   if ( $debug == 1 ) { rollback($setname, $setid, @photoids); }
}

sub rollback()
{
   my ($setname, $setid, @photoids) = @_;
   utf8::encode($setname);
   my $response;
   my $loop;

   print "Rollback for: $setname\n";

   # Delete photoset.
   if ( $setid != "" )
   {
      print "   Deleting photoset: $setname\n";
      $loop = 1;
      do
      {
         $response = $api->execute_method(
            'flickr.photosets.delete', {
            'api_key' => $auth_key,
            'auth_token' => $auth_token,
            'photoset_id' => $setid
         });
         if ( $response->{success} != 1 )
         {  
            print "ERROR: Could not delete photoset: $setid! (Try $loop)\n";
            print    "( ". $response->{error_message} ." )\n";
            $loop++;
         } else 
         {
            if ( $loop > 1 ) { print "Photoset deleted. (Try $loop)\n"; }
            $loop = 99;
         }
      } while ( $loop < $tries+1 );
   }

   # Delete photos via already uploaded ids.
   if ( @photoids > 0 )
   {
      foreach my $image ( @photoids )
      {
         print "   Deleting imageid: $image\n";
         $loop = 1;
         do
         {
            $response = $api->execute_method(
               'flickr.photos.delete', {
               'api_key' => $auth_key,
               'api_secret' => $auth_secret,
               'auth_token' => $auth_token,
               'photo_id' => $image 
            });
            if ( $response->{success} != 1 )
            {
               print "ERROR: Could not delete imageid: $image! (Try $loop)\n";
               print    "( ". $response->{error_message} ." )\n";
               $loop++;
            } else
            {
               if ( $loop > 1 ) { print "Deleted imageid: $image. (Try $loop)\n"; }
               $loop = 99;
            }
         } while ( $loop < $tries+1 );
      }
   }
}