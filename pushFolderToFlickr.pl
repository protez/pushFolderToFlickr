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
use XML::LibXML;

# Flickr authentication credentials. 
my $auth_key = '???';
my $auth_secret = '???';
my $auth_token = '???';

# Scriptname, version and process options.
my $version = "1.1";
my $tries = 10;
my $sleeponfail = 60;
my $debug = 0;

### MAIN ###
if ( $auth_key eq "???" || $auth_secret eq "???" || $auth_token eq "???" )
{
   print "ERROR: Script not configured correctly. Please apply for a flickr api key.\n";
   exit -1;
}

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

# Prepare some global variables.
my $dir = @ARGV[0];
my $setname = basename($dir);

# Initialize upload-module.
my $ua = Flickr::Upload->new({
   'key' => $auth_key,
   'secret' => $auth_secret
}); 
$ua->agent("Flickr::Upload::pushFolderToFlickr/$version"); 

# Initialize flickr core module.
my $api = new Flickr::API({
   'key' => $auth_key,
   'secret' => $auth_secret,
   'unicode' => 1
});

# Show some account stats.
my $response = flickrApiCall('flickr.people.getUploadStatus', {} );
if (! $response ) { exit -1; }

if ( $quiet == 0 ) { print "pushFolderToFlickr - V". $version ."\n\n"; }
if ( $quiet == 0 ) { print "Bandwidth summary:\n"; }
if ( $quiet == 0 ) { print "   Remaining KB: ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{remainingkb} ."\n"; }
if ( $quiet == 0 ) { print "   Used KB     : ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{usedkb} ."\n"; }
if ( $quiet == 0 ) { print "   Max KB      : ". $response->{tree}->{children}->[1]->{children}->[3]->{attributes}->{maxkb} ."\n\n"; }

# Fetch some data to coordinate uploads and photoset creation.
my $photosetlist = flickrGetPhotosets();
my $setExists = 0;
my $setid = getPhotosetId($setname);
my $photolist;
if ( $setid )
{
   if ( $quiet == 0 ) { print "Photoset already exists (ID $setid)\n"; }
   $photolist = flickrGetPhotosOfPhotoset($setid);
   $setExists = 1;
}
utf8::decode($setname);

# Start main engine.
uploadFolderToFlickr(); 

###
### Some usefull helper functions.
###

# This function executes the api call and handles errors.
# It will return "undef" if the api call could not be completed.
sub flickrApiCall
{
   my $cmd = shift;
   my $cmdargs = shift;
   my $args;

   my $authargs = {
      'api_key' => $auth_key,
      'auth_token' => $auth_token,
   }; 

   # Merge args
   foreach ( keys $authargs )
   {
      $args->{$_} = $authargs->{$_};
   }
   foreach ( keys $cmdargs )
   {
      $args->{$_} = $cmdargs->{$_};
   }

   # Execute API call.
   my $response;
   my $loop = 1;
   do
   {
      $response = $api->execute_method(
         $cmd, $args
      );

      if ( $response->{success} != 1 )
      {
         print "ERROR: API returned error for call: $cmd!\n";
         print    "( ". $response->{error_message} ." )\n";
         sleep($sleeponfail);
         $loop++;
      } else
      {
         if ( $loop > 1 ) { print "API call: $cmd successfully finished. (Try $loop)\n"; }
         $loop = 99;
      }
   } while ( $loop < $tries+1 );

   # Return undef if we could not complete the api call.
   if ( $loop == $tries+1 )
   {
      return undef;
   }

   return $response;
}

# This is the main function of this script. It uploads images to flickr and adds them
# to a photoset.
sub uploadFolderToFlickr
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

         my $tmp = $image;
         $tmp =~ s/\..*$//;
         if ( photoAlreadyExistsWithinPhotoset($tmp) )
         {
            if ( $quiet == 0 ) { print "Photo $image already exists within photoset...\n"; }
            next;
         }  

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
         flickrAddPicturesToPhotoset($setname, @photoids);
      }
   } 
   return; 
}

# This function is called by uploadFolderToFlicker to add images to a given photoset.
# The photoset will be created if it doesn't exist.
sub flickrAddPicturesToPhotoset
{
   my ($setname, @photoids) = @_; 

   # Create photoset if it doesn't already exists.
   if (! $setid )
   { 
      my $response = flickrApiCall('flickr.photosets.create', { 
         'title' => $setname,
         'primary_photo_id' => @photoids[0]
      });
      if (! $response ) { rollback($setname, "", @photoids); }
      $setid = $response->{tree}->{children}->[1]->{attributes}->{id};
   }

   foreach my $item (@photoids)
   {
      if ( $item != @photoids[0] )
      {
         print "Adding $item to $setid\n";
         $response = flickrApiCall('flickr.photosets.addPhoto', { 'photoset_id' => $setid,'photo_id' => $item });
         if (! $response ) { rollback($setname, @photoids); }
      }
   }
   if ( $debug == 1 ) { rollback($setname, @photoids); }
}

# This function fetches the complete list of photosets.
sub flickrGetPhotosets
{
   my $items;
   my $page = 1;
   my $pages = 1;

   do
   {
      my $response = flickrApiCall('flickr.photosets.getList', { 'page' => $page} );
      if (! $response ) { exit -1; }

      my $buffer  = $response->content;
      my $content = Compress::Zlib::memGunzip($buffer);
      my $parser = XML::LibXML->new();
      my $info = $parser->parse_string($content);

      my $nodes = $info->findnodes('/rsp/photosets');
      $pages = $nodes->[0]->findvalue('@pages');

      my $photosetNodes = $info->findnodes('//photoset');

      # Copy result into id-array.
      foreach my $node ( @{$photosetNodes} )
      {
         my $title = $node->getChildrenByTagName('title');
         utf8::encode($title);
         $items->{$node->getAttribute('id')} = $title;
      }
      $page++;
   } while ( $page <= $pages );

   return $items;
}

# After fetching a list of photosets this function finds the id of a given photoset.
sub getPhotosetId
{
   my $photosetname = shift;

   if ( $photosetlist )
   {
      foreach ( keys $photosetlist )
      {
         if ( $photosetlist->{$_} eq $photosetname )
         {
            return $_;
         }
      }
   }
   return undef;
}

# After looking up a photoset id, this function returns the list of images within this photoset.
sub flickrGetPhotosOfPhotoset()
{
   my $photosetid = shift;
   my $items;
   my $page = 1;
   my $pages = 1;

   do
   {
      my $response = flickrApiCall('flickr.photosets.getPhotos', {
         'photoset_id' => $photosetid,
         'page' => $page,
      });
      if (! $response ) { exit -1; }

      my $buffer  = $response->content;
      my $content = Compress::Zlib::memGunzip($buffer);
      my $parser = XML::LibXML->new();
      my $info = $parser->parse_string($content);

      my $nodes = $info->findnodes('/rsp/photoset');
      $pages = $nodes->[0]->findvalue('@pages');

      my $photoNodes = $info->findnodes('//photo');

      foreach my $node ( @{$photoNodes} )
      {
         $items->{$node->getAttribute('id')} = $node->getAttribute('title');
      } 
      $page++;

   } while ( $page <= $pages );

   return $items;
}

# Check wether the given photo already exists within the photoset (with id).
sub photoAlreadyExistsWithinPhotoset
{
   my $imagename = shift;

   if ( $photolist )
   {
      foreach ( keys $photolist )
      {
         if ( lc($imagename) eq lc($photolist->{$_}) )
         {
            return 1;
         }
      }
   }
   return undef;
}

# At a strange api behaviour or some not correctable errors, the script will rollback
# the actions done before. So there won't be any inconsistency (uploaded images and
# photosets).
sub rollback
{
   my ($setname, @photoids) = @_;
   utf8::encode($setname);
   my $response;
   my $loop;

   print "Rollback for: $setname\n";

   # Delete photoset.
   if ( $setExists == 0 )
   {
      print "   Deleting photoset: $setname\n";
      my $response = flickrApiCall('flickr.photosets.delete', {
         'photoset_id' => $setid
      });
   }

   # Delete already uploaded photos.
   if ( @photoids > 0 )
   {
      foreach my $image ( @photoids )
      {
         print "   Deleting imageid: $image\n";
         my $response = flickrApiCall('flickr.photos.delete', {
            'photo_id' => $image
         });
      }
   }
   exit -1;
}
