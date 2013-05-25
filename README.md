pushFolderToFlickr
==================

Upload whole folders to flickr via commandline. Images will be added to a photoset named as the source directory.

This perlscript has 2 simple commandline options:
1. Source directory which will be uploaded to flickr.
2. -q option (quiet). Only important status messages will be displayed.

Before you can use this script (pushFolderToFlickr.pl), you have to configure it by supplying an API key.
I've attached an addtional script to simplify this process (getFlickrAuthToken.pl). At the end of the
script the final auth data will be displayed. You have to add these lines to the main script to work
properly.

Any questions? Don't hesitate to contant me...
