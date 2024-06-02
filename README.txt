######################################################################
# $Id: README.txt 256 2010-01-01 14:40:30Z alba $
######################################################################

Schnuerpel is a collection of scripts used on server news.albasani.net.

Most of the scripts are written in Perl 5.
Development started with
- INN 2.4.x
- cleanfeed 20020501
- mysql 4.0.x
- Debian 3.1 for i386

Development now happens with
- mysql 5.0.x
- Ubuntu 8.04 for x64

Since Schnuerpel is not a monolithic piece of software it is quite
possible to use only selected parts or disable optional features,
e.g. mysql.

Scripts can be categorized into three groups according to the
environment they are used in:
- plain command line
- scheduled invocation through crond
- event triggered invocation by INN (access control, filters)

######################################################################
DIRECTORIES
######################################################################

bin
    Command line tools.

lib/Schnuerpel
    Various perl modules.

lib/Schnuerpel/INN
    Perl modules using data or functions provided by INN.

etc
    SQL statements to set up the database.

etc/Schnuerpel
    Example code for your Config.pm 

etc/filter
    Example code for your INN filters.

######################################################################
INSTALLATION
######################################################################

The interactive tools require two environment variables:

  SCHNUERPEL_DIR="/opt/schnuerpel"
  PERL5LIB="/opt/schnuerpel/lib:/opt/schnuerpel/etc"

