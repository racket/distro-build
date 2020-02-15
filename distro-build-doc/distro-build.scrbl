#lang scribble/manual
@(require scribble/bnf
          (for-label distro-build/config
                     distro-build/readme))

@title{Building Distributions of Racket}

The @filepath{distro-build} collection provides tools for creating a
Racket distribution---like the ones available at
@url{http://download.racket-lang.org}, but perhaps for different
versions or with different packages pre-installed.

The distribution-building tools are meant to be driven by a makefile
in the main Racket source repository, which is currently
@url{https://github.com/plt/racket}. See @filepath{INSTALL.txt} there
for general build information.

@; ----------------------------------------

@section{Site Configuration Modules}

A build farm is normally run via the @tt{installers}, @tt{site}, or
@tt{snapshot-site} target of the Racket repository's top-level
makefile. The latter two targets chain to the @tt{installers} target,
which expects a @tt{CONFIG=...} argument to specify a configuration
module file (or uses @filepath{build/site.rkt} as the default).

A site configuration module starts @racket[@#,hash-lang[]
@#,racketmodname[distro-build/config]] and uses keywords to specify
various options for the configuration. This format is described is
detail in @secref["distro-build-language"]. For now, it's enough to
know that there are various options, each of which is associated with
a keyword.

The machine where @exec{make installers} is run is the @deftech{server
machine}. The server machine first prepares packages for installation
on @deftech{client machines}. The site configuration's top-level entry
is consulted for a @racket[#:pkgs] and/or @racket[#:doc-search]
option, which overrides any @tt{PKGS} and/or @tt{DOC_SEARCH}
configuration from the makefile. A top-level @racket[#:test-pkgs]
entry in the configuration is added to @racket[#:pkgs] to determine
the packages that are prepared by the server.

When building installers that include the @racket['cs] variant,
@tt{make installer SETUP_MACHINE_FLAGS=-M} is recommended, because it
prepares the packages in a machine-independent format that can be
quickly recompiled on clients.

The site configuration file otherwise describes and configures
client machines hierarchically, where configuration options
propagate down the hierarchy when they are not overridden more
locally.

Each client is normally built by running commands via @exec{ssh},
where the client's host configured with @racket[#:host] (with and
optional @racket[#:port] and/or @racket[#:user]) indicate the
@exec{ssh} target. Each client machine must be set up with a
public-key authentication, because a direct @exec{ssh} is expected to
work without a password prompt. An exception is when the host is
@racket["localhost"] and user is @racket[#f], in which case a shell is
used directly instead of @exec{ssh}. When @exec{ssh} is used, @Flag{R}
is also used to create a tunnel back to the server, and the client by
default uses that tunnel for all communication, so the server by
default accepts only connections via @racket["localhost"].

On the client machine, all work is performed at a specified directory
as specified by @racket[#:dir]. The directory defaults to
@filepath{build/plt} (Unix or Mac OS) or @filepath{build\plt}
(Windows), except when the host is @racket["localhost"] and the client
is @racket[#f], in which case the current directory (i.e., the
server's directory) is used.

Normally, the client directory is a Git clone:

@itemlist[

  @item{If the directory exists already on a client machine (and the
    machine is not configured for ``clean'' mode), then if the
    directory contains a @filepath{.git} subdirectory, it is assumed
    to be a git clone and updated with @exec{git pull}. The @exec{git
    pull} operation can be disabled by specifying @racket[#:pull?] as
    @racket[#f], and it defaults to @racket[#f] in the case that
    @racket[#:dir] is not specified, the host is @racket["localhost"],
    and the user is @racket[#f].}

  @item{If the directory does not exist, a Git repository is cloned.
    The repository can be specified with @racket[#:repo]. By default,
    the server is used as the source Git repository (so that the
    server and client are in sync), which means that the server's
    directory must be a Git clone.}

]

Note that neither @exec{ssh} nor @exec{git} turn out to be needed when
the host is @racket["localhost"], the user is @racket[#f], and the
directory is not specified (which corresponds to the defaults in all
cases).

If a build fails for a machine, building continues on other machines.
Success for a given machine means that its installer ends up in
@filepath{build/installers} (and failure for a machine means no
installer) as recorded in the @filepath{table.rktd} file.

To use the @tt{site} makefile target, the configuration file must at
least provide a @racket[#:dist-base-url] value, which is a URL at which the
site will be made available. To use the @tt{snapshot-site} makefile
target, then @racket[#:site-dest] will need to be specified, normally as a
path that ends with the value produced by @racket[(current-stamp)].

Hint: When developing a configuration file, use an empty set of
packages to a configuration that works as quickly as possible. Then,
change the list of packages to the ones that you actually want in the
installers.


@; ----------------------------------------

@section{Machine Requirements}

Each Unix or Mac OS @tech{client machine} needs the following available:

@itemlist[

  @item{SSH server with public-key authentication (except @racket["localhost"])}
  
  @item{@exec{git} (unless the working directory is ready)}

  @item{@exec{gcc}, @exec{make}, etc.}

  @item{when creating a Windows installer (via cross-compilation),
        Nullsoft Scriptable Install System (NSIS) version 2.x with
        @exec{makensis} in @envvar{PATH}}

]

Each Windows @tech{client machine} needs the following:

@itemlist[

  @item{SSH server with public-key authentication, providing either a
    Windows command line (like freeSSHd) or bash with access to
    @exec{cmd.exe} (like Cygwin's @exec{opensshd})}
    
  @item{@exec{git} (unless the working directory is ready)}
  
  @item{Microsoft Visual Studio (version at least 9.0 and no more than 12.0), installed
    in the default folder:
     @filepath{C:\Program Files\Microsoft Visual Studio @nonterm{vers}}
    or
     @filepath{C:\Program Files (x86)\Microsoft Visual Studio @nonterm{vers}}}
     
  @item{Nullsoft Scriptable Install System (NSIS) version 2.x, installed
    in the default folder:
     @filepath{C:\Program Files\NSIS\makensis.exe}
    or
     @filepath{C:\Program Files (x86)\NSIS\makensis.exe}
    or installed so that @exec{makensis} in @envvar{PATH}}

]

Currently, Windows and Unix variants can be cross-compiled using a
same-versioned native Racket installation on a client machine that
runs Unix or Mac OS.

@; ----------------------------------------

@section[#:tag "distro-build-language"]{Site Configuration Language}

A site configuration module is normally written in the
@racketmodname[distro-build/config] language. The configuration
describes individual machines, and groups them with @racket[parallel]
or @racket[sequential] to indicate whether the machine's builds should
run sequentially or in parallel. Options specified at
@racket[parallel] or @racket[sequential] are propagated to each
machine in the group.

@defmodulelang[distro-build/config]

The @racketmodname[distro-build/config] language is like
@racketmodname[racket/base] except that the module body must have
exactly one expression (plus any number of definitions, etc.) that
produces a site-configuration value. The value is exported as
@racket[site-config] from the module. Any module can act as a
site-configuration module a long as it exports @racket[site-config] as
a site-configuration value.

Site-configuration values are created with @racket[sequential],
@racket[parallel], and @racket[machine]:

@deftogether[(
@defproc[(machine ...) site-config?]
@defproc[(parallel ... [config site-config?] ...) site-config?]
@defproc[(sequential ... [config site-config?] ...) site-config?]
)]{

Produces a site configuration based on the given keyword-based
options as described below. The @racket[sequential] function
produces a site configuration that runs each @racket[config]
sequentially. The @racket[parallel] function
produces a site configuration that runs each @racket[config]
in parallel.

Site-configuration keyword arguments (where @racket[_string*] means no
spaces, etc.):

@itemlist[

  @item{@racket[#:host _string*] --- defaults to @racket["localhost"]}

  @item{@racket[#:name _string] --- defaults to @racket[#:host]'s
    value; this string is recorded as a description of the installer
    and can be used in a generated table of installer links; see also
    @secref["name-format"]}

  @item{@racket[#:port _integer] --- SSH port for the client;
    defaults to @racket[22]}

  @item{@racket[#:user _string*-or-false] --- SSH user for the client;
    defaults to @racket[#f], which means the current user}

  @item{@racket[#:dir _path-string] --- defaults to
    @racket["build/plt"] or @racket["build\\plt"], or to the current
    directory if the host is @racket["localhost"] and the user is
    @racket[#f]}

  @item{@racket[#:env (list (list _string* _string) ...)] ---
    environment-variable settings to prefix all client-machine
    interactions for a Unix or Mac OS client; for example
    @racket['(("PATH" "/usr/local/bin:/usr/bin"))] configures the
    client machine's @envvar{PATH} enviornment variable to have
    only @filepath{/usr/local/bin} and @filepath{/usr/bin}}

  @item{@racket[#:server _string*] --- the address of the server as
    accessed by the client; when SSH remote tunneling works, then
    @racket["localhost"] should work to reach the server; defaults to
    the @tt{SERVER} makefile variable, which in turn defaults to
    @racket["localhost"]; see also @racket[#:server-hosts] and
    @racket[#:server-port], which must be at the configuration top
    level}

  @item{@racket[#:repo _string] --- the git repository for Racket;
    defaults to
    @filepath{http://@nonterm{server}:@nonterm{server-port}/.git};
    see also @racket[#:extra-repo-dir], which must be
    at the configuration top level}

  @item{@racket[#:pkgs (list _string* ...)] --- packages to install;
    defaults to the @tt{PKGS} makefile variable}

  @item{@racket[#:test-args (list _string ...)] --- arguments to
    @exec{raco test} as run in the installation-staging directory of a
    client after an installer is created, where testsing happens only
    if if a non-empty argument list is specified, if the client is not
    a source-runtime build, and if the client does not have a
    @racket[#:cross-target] or @racket[#:cross-target-machine]
    configuration; running @exec{raco test}
    will only work if @filepath{compiler-lib} is among the packages
    included in the distribution or included in a @racket[#:test-pkgs]
    configuration; defaults to @racket['()]}

  @item{@racket[#:test-pkgs (list _string* ...)] --- extra packages to
    install after an installer is created and before tests are run;
    note that @filepath{compiler-lib} may be needed to provide
    @exec{raco test} itself; the set of packages needed for all nested
    configurations should be included in a top-level @racket[#:pkgs]
    or @racket[#:test-pkgs] specification, so that the packages are
    prepared for use by clients; defaults to @racket['()]}

  @item{@racket[#:dist-base-url _string] --- a URL that is used to
    construct a default for @racket[#:doc-search] and
    @racket[#:dist-catalogs], where the constructed values are
    consistent with converting a build server's content into a
    download site; since URLs are constructed via relative paths, this
    URL normally should end with a slash}

  @item{@racket[#:doc-search _string] --- URL to install as the
    configuration for remote documentation searches in generated
    installers; @racket[""] is replaced with the PLT default; defaults
    to the @racket[#:dist-base-url] setting (if present) extended with
    @racket["doc/local-redirect/index.html"] or the @tt{DOC_SEARCH}
    makefile variable}

  @item{@racket[#:install-name _string] --- string used as the name of
    the installation for package operations in the @tt{user} package
    scope, where @racket[""] keeps the name as the Racket version; the
    default is @racket["snapshot"] if the value of @racket[#:release?]
    is @racket[#f], @racket[""] otherwise}

  @item{@racket[#:build-stamp _string] --- a string representing a
     build stamp, recorded in installers; the default is from the
     @tt{BUILD_STAMP} makefile variable or generated if the value of
     @racket[#:release?] is @racket[#f], @racket[""] otherwise}

  @item{@racket[#:dist-name _string] --- the distribution name;
    defaults to the @tt{DIST_NAME} makefile variable}

  @item{@racket[#:dist-base _string*] --- the distribution's
    installater name prefix; defaults to the @tt{DIST_BASE} makefile
    variable}

  @item{@racket[#:dist-dir _string*] --- the distribution's
    installation directory; defaults to the @tt{DIST_DIR} makefile
    variable}

  @item{@racket[#:dist-suffix _string*] --- a suffix for the
    installer's name, usually used for an operating-system variant;
    defaults to the @tt{DIST_SUFFIX} makefile variable}

  @item{@racket[#:dist-catalogs (list _string ...)] --- catalog URLs
    to install as the initial catalog configuration in generated
    installed, where @racket[""] is replaced with the PLT default
    catalogs; defaults to the @racket[#:dist-base-url] value (if
    present) extended with @racket["catalogs"] in a list followed by
    @racket[""]}

  @item{@racket[#:readme _string-or-procedure] --- the content of a
    @filepath{README} file to include in installers, or a function
    that takes a hash table for a configuration and returns a string;
    the default is the @racket[make-readme] function from
    @racketmodname[distro-build/readme]}

  @item{@racket[#:max-vm _real] --- maximum number of VMs allowed to
    run with this machine, counting the machine; defaults to
    @racket[1]}

  @item{@racket[#:vbox _string] --- Virtual Box machine name (as
    shown, for example, in the Virtual Box GUI); if provided, the
    virtual machine is started and stopped on the server as needed}

  @item{@racket[#:platform _symbol] --- @racket['unix],
    @racket['macosx], @racket['windows], @racket['windows/bash] (which
    means @racket['windows] though an SSH server providing
    @exec{bash}, such as Cygwin's), or @racket['windows/cmd] (which
    means @racket['windows] through an SSH server that expects
    @exec{cmd} commands); the @racket[_symbol] names the client
    machine's system, not the target for cross-compilation; defaults
    to @racket[(system-type)]}

  @item{@racket[#:configure (list _string ...)] --- arguments to
    @exec{configure}}

  @item{@racket[#:cross-target _string*] --- specifies a target for
    cross-compilation, which adds @DFlag{host}@tt{=}@racket[_string*]
    to the start of the list of @exec{configure} arguments; in
    addition, if no @racket[#:racket] value is provided, a native
    @exec{racket} executable for the client machine is created (by
    using @exec{configure} with no arguments) and used for
    cross-compilation in the same way as a @racket[#:racket] value;
    note that cross-compilation for the @racket['cs] variant may also
    also requires a @racket[#:cross-target-machine] specification,
    although it is inferred from @racket[#:cross-target] if possible}

  @item{@racket[#:cross-target-machine _string*] --- similar to
    @racket[#:cross-target], but used only for @racket[#:variant 'cs],
    and specifies the target machine for cross-compilation ofa
    as a string like @racket["ta6nt"]; use both
    @racket[#:cross-target-machine] and @racket[#:cross-target] unless
    the former can be inferred from the latter or unless options in
    @racket[#:configure] instead of @racket[#:cross-target] select the
    cross-build target
    @history[#:added "1.3"]}

  @item{@racket[#:racket _string-or-false] --- an absolute path to a
    native Racket executable to use for compilation, especially
    cross-compilation; if the value is @racket[#f], then the Racket
    executable generated for the client machine is used to prepare the
    installer, or a client-native executable is generated
    automatically if @racket[#:cross-target] or
    @racket[#:cross-target-machine] is specified; a non-@racket[#f]
    value for @racket[#:racket] is propagated to @racket[#:configure]
    via @DFlag{enable-racket}}

  @item{@racket[#:scheme _string-or-false] --- an absolute path to a
    directory containing Chez Scheme sources, used only for
    @racket[#:variant 'cs]; if the value is @racket[#f], then a build
    directory is created by cloning a Chez Scheme Git repository; a
    non-@racket[#f] value for @racket[#:scheme] is propagated to
    @racket[#:configure] via @DFlag{enable-scheme}
    @history[#:added "1.3"]}

  @item{@racket[#:target-platform _symbol] --- @racket['unix],
    @racket['macosx], or @racket['windows], or @racket[#f], indicating
    the target platform's type (which is different from the client
    system type in the case of cross-compilation); defaults to
    @racket[#f], which means that the target platform should be
    inferred from arguments such as @racket[#:cross-target]}

  @item{@racket[#:variant _symbol] --- @racket['3m], @racket['cgc], or
    @racket['cs], indicating the target build; defaults to
    @racket['3m]}

  @item{@racket[#:compile-any? _boolean] --- determines whether to
    build bytecode in machine-independent form, which works for all
    Racket variants but is slower to load; a @scheme[#t] value makes sense
    mainly for a source distirbution that includes built packages;
    defaults to @racket[#f]}

  @item{@racket[#:bits _integer] --- @racket[32] or @racket[64];
    affects Visual Studio mode}

  @item{@racket[#:vc _string*] --- provided to
    @filepath{vcvarsall.bat} to select the Visual Studio build mode;
    the default is @racket["x86"] or @racket["x86_amd64"], depending
    on the value of @racket[#:bits]}

  @item{@racket[#:sign-identity _string] --- provides an identity to
    be passed to @exec{codesign} for code signing on Mac OS (for a
    package or all executables in a distribution), where an empty
    string disables signing; the default is @racket[""]}

  @item{@racket[#:osslsigncode-args (list _string ...)] --- provides
    arguments for signing a Windows executable using
    @exec{osslsigncode}, where @Flag{n}, @Flag{t}, @Flag{in}, and
    @Flag{-out} arguments are supplied automatically}

  @item{@racket[#:hardened-runtime? _boolean] --- if true and if
    @racket[#:sign-identity] is non-empty, specifies the hardened
    runtime and appropriate entitlements while signing; the default is
    @racket[#t] if @racket[#:sign-identity] is non-empty
    @history[#:added "1.6"]}


  @item{@racket[#:client-installer-pre-process (list _string ...)]
    --- an executable path followed by initial arguments; the executable
    is run with the assembled distribution directory (added as an additional
    argument) before an installer file is created from the directory; the
    default is an empty list, which disables the pre-processing action
    @history[#:added "1.5"]}

  @item{@racket[#:client-installer-post-process (list _string ...)]
    --- an executable path followed by initial arguments; the executable
    is run with the installer path (added as an additional argument) before
    an installer file is uploaded from the client; the default is an empty list,
    which disable the post-processing action
    @history[#:added "1.2"]}

  @item{@racket[#:server-installer-post-process (list _path-string ...)]
    --- an executable path followed by initial arguments; the executable
    is run with the installer path added (as an additional argument) when
    creating a download site for an installer file on the server machine; the
    default is an empty list, which disable the post-processing action
    for the installer
    @history[#:added "1.2"]}

  @item{@racket[#:j _integer] --- parallelism for @tt{make} on Unix
    and Mac OS and for @exec{raco setup} on all platforms; defaults
    to @racket[1]}

  @item{@racket[#:timeout _number] --- numbers of seconds to wait
    before declaring failure; defaults to 30 minutes}

  @item{@racket[#:init _string-or-false] --- if non-@racket[#f], a
    command to run on a client and before any other commands; the
    default is @racket[#f]}

  @item{@racket[#:clean? _boolean] --- if true, then the build process
    on the client machine starts by removing @racket[#:dir]'s value;
    use @racket[#f] for a shared repo checkout; the default is
    determined by the @tt{CLEAN_MODE} makefile variable, unless
    @racket[#:host] is @racket["localhost"], @racket[#:user] is
    @racket[#f], and @racket[#:dir] is not specified, in which case
    the default is @racket[#f]}

  @item{@racket[#:pull? _boolean] --- if true, then the build process
    on the client machine starts by a @exec{git pull} in
    @racket[#:dir]'s value; use @racket[#f], for example, for a repo
    checkout that is shared with server; the default is @racket[#t],
    unless @racket[#:host] is @racket["localhost"], @racket[#:user] is
    @racket[#f], and @racket[#:dir] is not specified, in which case
    the default is @racket[#f]}

  @item{@racket[#:release? _boolean] --- if true, then create
    release-mode installers; the default is determined by the
    @tt{RELEASE_MODE} makefile variable}

  @item{@racket[#:source? _boolean] --- determines the default value for
    @racket[#:source-runtime?] and @racket[#:source-pkgs?] settings}

  @item{@racket[#:source-runtime? _boolean] --- if true, then create
    an archive that contains the run-time system in source form
    (possibly with built packages), instead of a platform-specific
    installer; a @racket[#t] value works best when used for a Unix
    build, since Unix clients typically have no
    native-library packages; the default is the value of
    @racket[#:source?]}

  @item{@racket[#:source-pkgs? _boolean] --- if true, then packages
    are included in the installer/archive only in source form; a true
    value works best when the @racket[#:source-runtime?] value is also
    @racket[#t]; the default is the value of @racket[#:source?]}

  @item{@racket[#:all-platform-pkgs? _boolean] --- if true, then for
    packages with platform-specific dependencies, the dependencies for
    all platforms are installed; a @racket[#t] value can make sense
    for a bundle that is primarily source but also includes native
    binaries for third-party libraries; the default is @racket[#f]

    @history[#:added "1.4"]}

  @item{@racket[#:versionless? _boolean] --- if true, avoids including
    the Racket version number in an installer's name or in the
    installation path; the default is determined by the
    @tt{VERSIONLESS_MODE} makefile variable}

  @item{@racket[#:mac-pkg? _boolean] --- if true, creates a
    @filepath{.pkg} for Mac OS (in single-file format) instead of a
    @filepath{.dmg}; the default is @racket[#f]}

  @item{@racket[#:tgz? _boolean] --- if true, creates a
    @filepath{.tgz} archive instead of an installer; the default is
    @racket[#f]}

  @item{@racket[#:pause-before _nonnegative-real] --- a pause in
    seconds to wait before starting a machine, which may help a
    virtual machine avoid confusion from being stopped and started too
    quickly; the default is @racket[0]}

  @item{@racket[#:pause-after _nonnegative-real] --- a pause in
    seconds to wait after stopping a machine; the default is
    @racket[0]}

  @item{@racket[#:custom _hash-table] --- a hash table mapping
    arbitrary keywords to arbitrary values; when a value for
    @racket[#:custom] is overriden in a nested configuration, the new
    table is merged with the overriden one; use such a table for
    additional configuration entries other than the built-in ones,
    where additional entires may be useful to a @racket[#:readme]
    procedure}

]

Top keywords (expected only in the configuration top-level):

@itemlist[

  @item{@racket[#:server-port _integer] --- the port of the server as
    accessed by the client, and also the port started on clients to
    tunnel back to the server; defaults to the @tt{SERVER_PORT}
    makefile variable, which in turn defaults to @racket[9440]}

  @item{@racket[#:server-hosts (list _string* ...)] --- addresses that
    determine the interfaces on which the server listens; an empty
    list means all of the server's interfaces, while @racket[(list
    "localhost")] listens only on the loopback device; defaults to the
    @tt{SERVER_HOSTS} makefile variable split on commas, which in turn
    defaults to @racket[(list "localhost")]}

  @item{@racket[#:extra-repo-dir _path-string-or-false] --- a
    server-side directory that contains additional Git repositories to
    be served to clients, normally Chez Scheme with its submodules;
    any subdirectory that constains a @filepath{.git} directory will
    be prepared with @exec{git update-server-info}, and any repository
    clones created by clients (other than the main Racket repository)
    will use the served directory; updating on clients requires that
    each served repository has a @filepath{master} branch; defaults to
    @racket[#f], which disables repository redirection on clients}

  @item{@racket[#:site-dest _path-string] --- destination for
    completed build, used by the @tt{site} and @tt{snapshot-site}
    makefile targets; the default is @racket["build/site"]}

  @item{@racket[#:pdf-doc? _boolean] --- whether to build PDF
    documentation when assembling a site; the default is @racket[#f]}

  @item{@racket[#:email-to (list _string ...)] --- a list of addresses
     to receive e-mail reporting build results; mail is sent via
     @exec{sendmail} unless @racket[#:smtp-...] configuration is
     supplied}

  @item{@racket[#:email-from _string] --- address used as the sender
    of e-mailed reports; the first string in @racket[#:email-to] is
    used by default}

  @item{@racket[#:smtp-server _string*],
        @racket[#:smtp-port _string*],
        @racket[#:smtp-connect _symbol],
        @racket[#:smtp-user _string-or-false]
        @racket[#:smtp-password _string-or-false]
    --- configuration for sending e-mail through SMTP instead of
    @exec{sendmail}; the @racket[#:smtp-port] default (@racket[25],
    @racket[465], or @racket[587]) is picked based on
    @racket[#:smtp-connect], which can be @racket['plain],
    @racket['ssl], or @racket['tls] and defaults to @racket['plain];
    supply a non-@racket[#f] @racket[#:smtp-user] and
    @racket[#:smtp-password] when authentication is required by the
    server}

  @item{@racket[#:site-help _hash-table] --- hash table of extra
    ``help'' information for entries on a web page created by the
    @tt{site} and @tt{snapshot-site} makefile targets; the hash keys
    are strings for row labels in the download table (after splitting
    on @litchar{|} and removing @litchar["{"]...@litchar["}"]), and
    the values are X-expressions (see @racketmodname[xml]) for the
    help content}

  @item{@racket[#:site-title _string] --- title for the main page
    generated by the @tt{site} or @tt{snapshot-site} makefile target;
    the default is @racket["Racket Downloads"]}

  @item{@racket[#:max-snapshots _number] --- number of snapshots to
    keep, used by the @tt{snapshot-site} makefile target; defaults
    to @racket[5]}

  @item{@racket[#:week-count _number-or-false] ---
   if not @racket[#f], keeps one snapshot per day for the last
   week as well as one snapshot per week for the number of week
   specified; if set, then @racket[#:max-snapshots] is ignored;
   defaults to @racket[#f]}

  @item{@racket[#:plt-web-style? _boolean] --- indicates whether
    @racket[plt-web] should be used to generate a site or snapshot
    page; the default is @racket[#t]}

  @item{@racket[#:fail-on-client-failures _boolean] --- if true, failure
    on any build client causes the build server to exit with a non-zero
    return code; the default is @racket[#f]
    @history[#:added "1.1"]}
]}


@deftogether[(
@defproc[(site-config? [v any/c]) boolean?]
@defproc[(site-config-tag [config site-config?])
         (or/c 'machine 'sequential 'parallel)]
@defproc[(site-config-options [config site-config?])
         (hash/c keyword? any/c)]
@defproc[(site-config-content [config site-config?])
         (listof site-config?)]
)]{

Recognize and inspect site configurations.}


@defparam[current-mode s string?]{

A parameter whose value is the user's requested mode for this
configuration, normally as provided via the makefile's
@tt{CONFIG_MODE} variable. The default mode is @racket["default"]. The
interpretation of modes is completely up to the site configuration
file.}


@defproc[(current-stamp) string?]{

Returns a string to identify the current build, normally a combination
of the date and a git commit hash.}


@; ----------------------------------------

@section{READMEs}

@defmodule[distro-build/readme]{The
@racketmodname[distro-build/readme] library provides functions for
constructing a @filepath{README} file's content. Each function takes a
hash table mapping configuration keywords to values.}

@defproc[(make-readme [config hash?]) string?]{

Produces basic @filepath{README} content, using information about the
distribution and the Racket license. The content is constructed using
@racket[config] keys such as @racket[#:name], @racket[#:target-platform],
@racket[#:dist-name], and @racket[#:dist-catalogs], and sometimes
@racket[current-stamp]. Some content depends on the result of
@racket[(readme-system-type config)].}


@defproc[(make-macosx-notes [config hash?]) string?]{

Produces @filepath{README} content to tell Mac OS users how to install a
distribution folder. This function is used by @racket[make-readme] when
@racket[#:platform] in @racket[config] is @racket['macosx].}


@defproc[(readme-system-type [config hash?]) (or/c 'unix 'macosx 'windows)]{

Determines the kind of platform for a generated @filepath{README}
file:

@itemlist[

 @item{If @racket['#:target-platform] has a non-@racket[#f] value in
       @racket[config], the value is returned.}

 @item{Otherwise, if @racket['#:cross-target] has a string value, then
       a system type is inferred if it contains any of the following
       fragments: @litchar{mingw} implies @racket['windows],
       @litchar{darwin} implies @racket['macosx], and @litchar{linux}
       implies @racket['unix].}

 @item{If the above fail, the value of @racket['#:platform] is
       returned, if it is mapped in @racket[config].}

 @item{As a last resort, @racket[(system-type)] is returned.}

]}

@; ----------------------------------------

@section[#:tag "name-format"]{Names and Download Pages}

The @racket[#:name] value for an installer is used in an HTML table of
download links by the @tt{site} or @tt{snapshot-site} targets. The
names are first sorted. Then, for the purposes of building the table,
a @litchar["|"] separated by any number of spaces within a name is
treated as a hierarchical delimiter, while anything within
@litchar["{"] and @litchar["}"] in a hierarchical level is stripped
from the displayed name along with surrounding spaces (so that it can
affect sorting without being displayed). Anything after
@litchar[";\x20"] within a @litchar{|}-separated part is rendered as a
detail part of the label (e.g., in a smaller font).

For example, the names

@racketblock[
  "Racket | {2} Linux | 32-bit"
  "Racket | {2} Linux | 64-bit; built on Ubuntu"
  "Racket | {1} Windows | 32-bit"
  "Racket | {1} Windows | 64-bit"
  "Racket | {3} Source"
]

are shown (actually or conceptually) as

@verbatim[#:indent 2]|{
  Racket
   Windows
     [32-bit] <built on Ubuntu>
     [64-bit]
   Linux
     [32-bit]
     [64-bit]
   [Source]
}|

where the square-bracketed entries are hyperlinks and the
angle-bracketed pieces are details.

@; ----------------------------------------

@section{Examples}

Here are some example configuration files.

@subsection{Single Installer}

The simplest possible configuration file is

@codeblock{
  #lang distro-build/config
  (machine)
}

In fact, this configuration file is created automatically as
@filepath{build/site.rkt} (if the file does not exist already) and
used as the default configuration. With this configuration,

@commandline{make installers}

creates an installer in @filepath{build/installers} for the platform
that is used to create the installer.


@subsection{Installer Web Page}

To make a web page that serves both a minimal installer and packages,
create a @filepath{site.rkt} file with

@codeblock{
 #lang distro-build/config

 (sequential
  ;; The packages that will be available:
  #:pkgs '("main-distribution")
  ;; FIXME: the URL where the installer and packages will be:
  #:dist-base-url "http://my-server.domain/snapshot/"
  (machine
   ;; FIXME: the way the installer is described on the web page:
   #:name "Minimal Racket | My Platform" 
   ;; The packages in this installer:
   #:pkgs '()))
}

then

@commandline{make site CONFIG=site.rkt}

creates a @filepath{build/site} directory that you can move to your
web server's @filepath{snapshot} directory, so that
@filepath{build/site/index.html} is the main page, and so on.


@subsection{Accumulated Shapshots Web Page}

To make a web site that provides some number (5, by default) of
snapshots, use @racket[(current-stamp)] when constructing the
@racket[#:dist-base-url] value. Also, use @racket[(current-stamp)] as
the directory for assembling the site:

@codeblock{
 #lang distro-build/config
 (sequential
  ;; The packages that will be available:
  #:pkgs '("gui-lib")
  ;; FIXME: the URL where the installer and packages will be:
  #:dist-base-url (string-append "http://my-server.domain/snapshots/"
                                 (current-stamp) "/")
  ;; The local directory where a snapshot is written
  #:site-dest (build-path "build/site" (current-stamp))
  (machine
   ;; FIXME: the way the installer is described on the web page:
   #:name "Minimal Racket | My Platform" 
   ;; The packages in this installer:
   #:pkgs '()))
}

Then,

@commandline{make snapshot-site CONFIG=site.rkt}

creates a @filepath{build/site} directory that you can move to your web
server's @filepath{snapshots} directory, so that @filepath{build/site/index.html} is the
main page that initially points to @filepath{build/site/@nonterm{stamp}/index.html},
and so on. To make a newer snapshot, update the Git repository, leave
@filepath{build/site} in place, and run

@commandline{make snapshot-site CONFIG=site.rkt}

again. The new installers will go into a new <stamp> subdirectory, and
the main @filepath{index.html} file will be rewritten to point to them.


@subsection{Multiple Platforms}

A configuration module that drives multiple clients to build
installers might look like this:

@codeblock{
    #lang distro-build/config
   
    (sequential
     #:pkgs '("drracket")
     #:server-hosts '() ; Insecure? See below.
     (machine
      #:desc "Linux (32-bit, Precise Pangolin)"
      #:name "Ubuntu 32"
      #:vbox "Ubuntu 12.04"
      #:host "192.168.56.102")
     (machine
      #:desc "Windows (64-bit)"
      #:name "Windows 64"
      #:host "10.0.0.7"
      #:server "10.0.0.1"
      #:dir "c:\\Users\\racket\\build\\plt"
      #:platform 'windows
      #:bits 64))
}

The configuration describes using the hosts @racket["192.168.56.1"]
and @racket["10.0.0.7"] for Linux and Windows builds, respectively,
which are run one at a time.

The Linux machine runs in VirtualBox on the server machine (in a
virtual machine named @filepath{Ubuntu 12.04}). It contacts the server
still as @tt{localhost}, and that works because the SSH connection to
the Linux machine creates a tunnel (at the same port as the server's,
which defaults to 9440).

The Windows machine uses freeSSHd (not a @exec{bash}-based SSH server
like Cygwin) and communicates back to the server as
@racket["10.0.0.1"] instead of using an SSH tunnel. To make that work,
@racket[#:server-hosts] is specified as the empty list to make the
server listen on all interfaces (instead of just
@racket["localhost"])---which is possibly less secure than the default
restriction that allows build-server connections only via
@racket["localhost"].

With this configuration file in @filepath{site.rkt},

@commandline{make installers CONFIG=site.rkt}

produces two installers, both in @filepath{build/installers}, and a
hash table in @filepath{table.rktd} that maps
@racket["Linux (32-bit, Precise Pangolin)"] to the Linux installer
and @racket["Windows (64-bit)"] to the Windows installer.
