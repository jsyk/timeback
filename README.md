timeback-machine
================

Author: Jaroslav Sykora <http://www.jsykora.info/>

Simple & fast backup tool that creates complete snapshot views of the backup hiearchy on each run,
with automatic data de-duplication in a hashed object storage.

Runs on Linux and Windows, with perl.
Requires a filesystem with the hard-link support (basically all Linux, and Windows NTFS. Cannot run on FAT.)


Configuration
-------------

Configuration files are specific to each host (computer) that the tool is running on. 
Configuration files are stored in the "config/$hostname" directory, where $hostname is the name of the computer.
This allows having the tool installed on an USB stick and use it to back-up multiple different computers in turn.

Configuration files can have any extension, and there can be one or more of them. All configuration files
are loaded, merged and parsed during program start-up.

Each line in the configuration file shall be the directory name where backup should start its recursive descent.
An example of a content of a configuration file on a Windows machine is:

D:/Mail
D:/Docs
D:/Documents

.. or in case of Linux system:

/home/user/Photos
/home/user/Documents

The backup is run recursively from each starting directory mentioned in configuration files.
Please use absolute directory names.

The second option is to REMOVE a specific directory sub-tree from the backup action.
This is done by preceeding the directory name with the minus "-" character.
For example:

D:/Documents
-D:/Documents/Tables/tmp

This feature is useful when you need to backup a tree, but then skip some specific directory
down below inside that backup tree. In the example above the timeback-machine will backup 
everything under D:/Documents, except when it reaches the folder D:/Documents/Tables/tmp, which will be skipped.


Backup
------

To perform a backup, run the timeback-machine.pl script. Perl is required.

The first time the timeback-machine is running it creates the directories "db" and "views".
The "db" is an object storage for the backups. The user should not change anything in the "db" directory.
The "views" contain backup snapshot views. These can be used to freely browse the backup and restore files from it.
Inside the "views" directory there is a sub-directory with the hostname, and then a sub-sub-directory with the date 
and time labels when the backup was run.
For example, on the computer named "nibbler" we may find this structure:

views/nibbler/2019-03-22_21-48-16

The above view represents a backup performed on the nibbler computer on 22 March 2019 at 21:48:16.
Inside this view the user finds the complete directory snapshot. For example:

views/nibbler/2019-03-22_21-48-16/home/user/Photos ...
views/nibbler/2019-03-22_21-48-16/home/user/Documents ...

Files inside the views are hard-linked to so-called "body" files stored inside the object storage "db".
When a file is encoutered the first time during a backup run, its contents is hashed (SHA256) and stored inside the "db" 
and linked into the current view. The next time the same file is backed-up, a new hard-link will be created inside 
the new snapshot view into the already existing "body" file in the "db". This operation costs very little backup disk
space and runs very fast.
Files are identifed inside the db by their content. Therefore when a source file changes (e.g. a Word document is saved with
a new version), the contents changes, and thus a new "body" file will be created in the "db" during the next
back-up and referenced in the new snapshot view. Note the existing snapshot views continue to link to the previous 
"body" file version. Therefore each view truly represents a snapshot of the filesystem at the backup time,
and these snapshot are lightweight since they link to object storage, which is ensuring that exactly one copy
of a file version is ever stored on the backup media.


Notes
------
To find orphan bodies:
    find *  -links -2 -type f -name body
TODO:
    - remove orphans (including their name and parent dir)
