## libwiki

A simple shell library to assist in publishing files on a wiki.

Currently implemented are:
* Dokuwiki
* Mediawiki

### Configuration

The library expects a configurationfile in the location:

```~/.libwiki.ini```

This configuration file is an ini style configuration. Each section defines
a wiki. The section names can be used when performing actions with the functions
in a shellscript.

Each section can have the following keywords:

```type```

This defines the type of wiki. Currently it can have two options:
* dokuwiki
* mediawiki

```url```

This is the URL to the wiki (API).

```user```

The user name that should be used to authenticate to the wiki.

```password```

The password that should be used to authenticate to the wiki.

### Using the library

First the profile from the configuration file that should be used has to be defined:

```wiki profile <profilename>```

Then the connection to the API needs to be setup:

```wiki connect```

Lastly a file can be saved to the wiki. This can be done with a reference to a
file:

```wiki save <pagename> <filename>```

or the data can be read from stdin:

```wiki save <pagename> -```


