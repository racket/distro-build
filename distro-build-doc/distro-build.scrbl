#lang scribble/manual
@(require scribble/bnf
          (for-label (except-in racket/base
                                #%module-begin)
                     racket/contract/base
                     distro-build/config
                     distro-build/readme)
          (only-in scribble/decode splice)
          "private/version-guard.rkt")

@(version-guard (require (for-label distro-build/main-distribution)))

@title{Building Distributions of Racket}

The @filepath{distro-build} collection provides tools for creating a
Racket distribution---like the ones available at
@url{http://download.racket-lang.org}, but perhaps for different
versions or with different packages pre-installed.

The distribution-building tools are meant to be driven by a makefile
in the main Racket source repository, which is currently
@url{https://github.com/racket/racket}. See @filepath{build.md} there
for general build information.

@table-of-contents[]

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

Each client is either a remote machine accessible by @exec{ssh}, a
VirtualBox virtual machine to run on the server machine, or a Docker
container to run on the server machine. For a remote machine or
VirtualBox machine, client build commands are run via @exec{ssh},
where the client's host configured with @racket[#:host] (with and
optional @racket[#:port] and/or @racket[#:user]) indicate the
@exec{ssh} target. Each client machine must be set up with a
public-key authentication, because a direct @exec{ssh} is expected to
work without a password prompt. An exception is when the host is
@racket["localhost"] and user is @racket[#f], in which case a shell is
used directly instead of @exec{ssh}. When @exec{ssh} is used, @Flag{R}
is also used to create a tunnel back to the server, and the client by
default uses that tunnel for all communication, so the server by
default accepts only connections via @racket["localhost"]. For a
client as a Docker container, @racket[#:docker] specifies an image
name, @racket[#:host] is used as a container name, and @exec{ssh} is
not used. Any container that already exists with the @racket[#:host]
name is used as-is, to support incremental builds.

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

  @item{when creating a Mac OS installer on Unix via cross-compilation,
        @exec{mkfs.hfsplus}, @exec{hfsplus}, and @exec{dmg} in @envvar{PATH},
        as well as @exec{rcodesign} to support code signing and notarization}

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

  @item{@racket[#:host _string*] --- defaults to @racket["localhost"];
    if @racket[#:docker] is provided, this host name is used as a
    Docker container name}

  @item{@racket[#:name _string] --- defaults to @racket[#:host]'s
    value; this string is recorded as a description of the installer
    and can be used in a generated table of installer links; see also
    @secref["name-format"]}

  @item{@racket[#:port _integer] --- SSH port for the client;
    defaults to @racket[22]}

  @item{@racket[#:user _string*-or-false] --- SSH user for the client;
    defaults to @racket[#f], which means the current user}

  @item{@racket[#:dir _path-string-or-symbol] --- normally defaults to
    @racket["build/plt"] or @racket["build\\plt"], but defaults to the current
    directory if @deftech{local mode} is enabled: @racket[#:host] is @racket["localhost"],
    @racket[#:user] is @racket[#f], @racket[#:configure] is @racket['()],
    @racket[#:cross-target] is @racket[#f], and
    @racket[#:cross-target-machine] is @racket[#f]; for other defaults,
    @tech{local mode} depends on @racket[#:dir] also being unspecified so
    that its default is used; a symbol, instead of a path string, does not
    generate an installer and instead builds for use by later
    configurations that have the same @racket[#:variant] and the
    same symbol for @racket[#:racket]; a symbol is allowed only for a
    @racket[#:docker] configuration, and discard an existing Docker
    container when changing the symbol

    @history[#:changed "1.17" @elem{Made @tech{local mode} depend on
                                    @racket[#:configure],
                                    @racket[#:cross-target], and
                                    @racket[#:cross-target-machine].}
             #:changed "1.20" @elem{Added symbol mode to cooperate with
                                    @racket[#:racket].}]}

  @item{@racket[#:env (list (list _string* _string) ...)] ---
    environment-variable settings to prefix all client-machine
    interactions for a Unix or Mac OS client; for example
    @racket['(("PATH" "/usr/local/bin:/usr/bin"))] configures the
    client machine's @envvar{PATH} enviornment variable to have
    only @filepath{/usr/local/bin} and @filepath{/usr/bin}}

  @item{@racket[#:server _string*] --- the address of the server as
    accessed by the client (except for Docker clients); when SSH remote tunneling works, then
    @racket["localhost"] should work to reach the server; defaults to
    the @tt{SERVER} makefile variable, which in turn defaults to
    @racket["localhost"]; see also @racket[#:server-hosts] and
    @racket[#:server-port], which must be at the configuration top
    level}

  @item{@racket[#:repo _string] --- the git repository for Racket;
    defaults to
    @filepath{http://@nonterm{server}:@nonterm{server-port}/.git},
    except for Docker clients, which access the server's directory
    directly; see also @racket[#:extra-repo-dir], which must be
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
    default is @racket[""]

    @history[#:changed "1.17" @elem{Made the default always
                                    @racket[""] independent of
                                    @racket[#:release?].}]}

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
    installer's name, usually used for an operating system variant; defaults to the
    @tt{DIST_SUFFIX} makefile variable}

  @item{@racket[#:dist-vm-suffix _string*] --- a suffix for the
    installer's name, usually used for a Racket virtual machine
    variant, added after @racket[#:dist-suffix]; defaults to
    @racket[""]}

  @item{@racket[#:dist-aliases (list (list _string*-or-false
     _string*-or-false _string*-or-false) ...)] --- a list of
     @racket[_base]--@racket[_suffix]--@racket[_vm-suffix] lists
     representing additional names to link for the installer in a
     download site, where @racket[#f] as a list element means ``the
     same as for the main name'' and where the first alias is used for
     a ``current'' link when enabled at a download site; a list with
     the @racket[#:dist-base], @racket[#:dist-suffix], and
     @racket[#:dist-vm-suffix] values is effectively appended to the
     end of the @racket[#:dist-aliases] list if not present already;
     defaults to @racket['()].

    @history[#:added "1.9"]}

  @item{@racket[#:dist-catalogs (list _string ...)] --- catalog URLs
    to install as the initial catalog configuration in generated
    installer, where @racket[""] is replaced with the PLT default
    catalogs; defaults to the @racket[#:dist-base-url] value (if
    present) extended with @racket["catalog/"] in a list followed by
    @racket[""]}

  @item{@racket[#:pref-defaults _list] --- preference defaults to
    merge into a @filepath{racket-prefs.rktd} file in a distribution,
    which is used to initialize preferences when the user has no
    Racket preferences file already; each list item must be a
    2-element list where the first element is a symbol
    @history[#:added "1.18"]}

  @item{@racket[#:readme _string-or-procedure] --- the content of a
    @filepath{README} file to include in installers, or a function
    that takes a hash table for a configuration and returns a string;
    the default is the @racket[make-readme] function from
    @racketmodname[distro-build/readme]}

  @item{@racket[#:max-vm _real] --- for VirtualBox clients, the maximum
    number of VirtualBox virtual machines allowed to
    run concurrently with this machine, counting the machine; defaults to
    @racket[1]}

  @item{@racket[#:max-parallel _real] --- the maximum number of
    clients to run in parallel; defaults to @racket[+inf.0]

    @history[#:added "1.20"]}

  @item{@racket[#:vbox _string] --- VirtualBox machine name (as
    shown, for example, in the Virtual Box GUI); if provided, the
    virtual machine is started and stopped on the server as needed}

  @item{@racket[#:docker _string] --- Docker image name; if provided
    and @racket[#:vbox] is not provided, then a container using the
    @racket[#:host] name is created if it does not already exist,
    started if it is not already running, and stopped on the server
    after building; the image @racket["racket/distro-build"] is
    suitable as a generic Linux image, and an image such as
    @racket["racket/distro-build:i386-linux"] is suitable for building
    for a specific architecture

    @history[#:added "1.8"]}

  @item{@racket[#:docker-platform _string-or-false] --- Docker image
    platform; specifies a platform other than the default one for a
    host and @racket[#:docker] image, which is useful when multiple
    platforms are supported by both the image and host machine;
    however, specifying a platform-specific Docker image like
    @racket["racket/distro-build:i386-linux"] is better when running
    multiple platforms on the same host; defaults to @racket[#f],
    which means a default or image-determined platform

    @history[#:added "1.14"]}

  @item{@racket[#:platform _symbol] --- @racket['unix],
    @racket['macosx], @racket['windows], @racket['windows/bash] (which
    means @racket['windows] though an SSH server providing
    @exec{bash}, such as Cygwin's), or @racket['windows/cmd] (which
    means @racket['windows] through an SSH server that expects
    @exec{cmd} commands); the @racket[_symbol] names the client
    machine's system, not the target for cross-compilation; defaults
    to @racket[(system-type)]}

  @item{@racket[#:configure (list _string ...)] --- arguments to
    @exec{configure}; if @racket["--disable-portable"] is not present,
    then @racket["--enable-portable"] is added to the start of the
    list; defaults to @racket['()]}

  @item{@racket[#:cross-target _string*-or-false] --- specifies a target for
    cross-compilation when a @racket[_string*], which adds @DFlag{host}@tt{=}@racket[_string*]
    to the start of the list of @exec{configure} arguments; in
    addition, if no @racket[#:racket] value is provided, a native
    @exec{racket} executable for the client machine is created (by
    using @exec{configure} with no arguments) and used for
    cross-compilation in the same way as a @racket[#:racket] value;
    note that cross-compilation for the @racket['cs] variant may also
    also requires a @racket[#:cross-target-machine] specification,
    although it is inferred from @racket[#:cross-target] if possible;
    the default for @racket[#:cross-target] is @racket[#f]}

  @item{@racket[#:cross-target-machine _string**-or-false] --- similar to
    @racket[#:cross-target] when a @racket[_string*], but used only for @racket[#:variant 'cs],
    and specifies the target machine for cross-compilation
    as a string like @racket["ta6nt"]; use both
    @racket[#:cross-target-machine] and @racket[#:cross-target] unless
    the former can be inferred from the latter or unless options in
    @racket[#:configure] instead of @racket[#:cross-target] select the
    cross-build target

    @history[#:added "1.3"]}

  @item{@racket[#:racket _string-or-symbol-false] --- an absolute path to a
    native Racket executable to use for compilation, especially
    cross-compilation, or a symbol that uses a Racket built by an earlier
    configuration that uses the symbol for @racket[#:dir]; if the value is @racket[#f], then the Racket
    executable generated for the client machine is used to prepare the
    installer, or a client-native executable is generated
    automatically if @racket[#:cross-target] or
    @racket[#:cross-target-machine] is specified; a non-@racket[#f]
    value for @racket[#:racket] is propagated to @racket[#:configure]
    via @DFlag{enable-racket}; a symbol is allowed for @racket[#:racket]
    only for a @racket[#:docker] configuration, and discard an existing Docker
    container when changing the symbol

    @history[#:changed "1.20" @elem{Added symbol mode to cooperate with
                                    @racket[#:dir].}]}

  @item{@racket[#:scheme _string-or-false] --- obsolete; was an
    absolute path to a directory containing Chez Scheme sources
    @history[#:added "1.3"]}

  @item{@racket[#:target-platform _symbol] --- @racket['unix],
    @racket['macosx], or @racket['windows], or @racket[#f], indicating
    the target platform's type (which is different from the client
    system type in the case of cross-compilation); defaults to
    @racket[#f], which means that the target platform should be
    inferred from arguments such as @racket[#:cross-target]}

  @item{@racket[#:variant _symbol] --- @racket['bc], @racket['3m] (as
    a synonym for @racket['bc]), @racket['cgc], or @racket['cs],
    indicating the target build; defaults to @racket['cs] or
    @racket['bc] depending on the running Racket implementation

    @history[#:changed "1.13" @elem{Changed the default to depend on
                                    the running Racket implementation.}]}

  @item{@racket[#:compile-any? _boolean] --- determines whether to
    build bytecode in machine-independent form, which works for all
    Racket variants but is slower to load; a @scheme[#t] value makes
    sense mainly for a source distribution that includes built
    packages or an installer used to drive machine-independent package
    builds; defaults to @racket[#f]}

  @item{@racket[#:recompile-cache _symbol-or-false] --- if not @racket[#f],
    identifies a cache for compiled files that can be shared across
    Docker-based machines that used the same @racket[#:recompile-cache]
    symbol; a symbol is allowed only for a
    @racket[#:docker] configuration, and discard an existing Docker
    container when changing the symbol

    @history[#:added "1.20"]}

  @item{@racket[#:bits _integer] --- @racket[32] or @racket[64];
    affects Visual Studio mode}

  @item{@racket[#:vc _string*] --- provided to
    @filepath{vcvarsall.bat} to select the Visual Studio build mode;
    the default is @racket["x86"] or @racket["x86_amd64"], depending
    on the value of @racket[#:bits]}

 @item{@racket[#:sign-identity _string] --- provides an identity to
    be passed to @exec{codesign} for code signing on Mac OS (for a
    package or a disk image and all executables in the image), where an empty
    string disables signing (unless @racket[#:sign-cert-config]
    provides a configuration); the default is @racket[""]}

  @item{@racket[#:sign-cert-config _hash-or-false] --- configures
    signing for Mac OS (for a package or for a disk image and all
    executables within the image) via @exec{rcodesign}; the required
    keys are @racket['p12-file] as a path and
    @racket['p12-password-file] as a path, and the optional key
    @racket['p12-dir] can be included as a path; if @racket['p12-dir]
    is specified and the client machine is a Docker container, the
    file paths are relative to the directory path on the server, otherwise
    the file paths are client-machine paths; beware that adding or changing @racket['p12-dir]
    requires recreating a Docker container; defaults to @racket[#f]

    @history[#:added "1.19"]}

  @item{@racket[#:notarization-config _hash-or-false] --- configures
    notarization of a signed Mac OS @filepath{.dmg} bundle via
    @exec{xcrun notarytool} and @exec{xcrun stapler} or via @exec{rcodesign}; the required keys
    for @exec{xcrun notarytool} are @racket['primary-bundle-id] as a string, @racket['user] as a
    string, @racket['team] as a
    string, and @racket['app-specific-password-file] as a string that
    is a path that contains a password; the required key for @exec{rcodesign}
    is @racket['api-key-file] as a string; the allowed optional keys are
    @racket['app-specific-password-dir] as a string for a server-machine path
    that @racket['app-specific-password-file] or @racket['api-key-file] is relative to when
    the client machine is a Docker container (otherwise, the file is a client-machine path),
    @racket['wait-seconds] as a nonnegative exact integer (defaults to
    @racket[120]) and @racket['error-on-fail?] as a boolean (defaults
    to @racket[#t]; beware that adding or changing @racket['app-specific-password-dir]
    requires recreating a Docker container)

    @history[#:changed "1.15" @elem{Added @racket['team] and changed
                                    @racket['wait-seconds] default to @racket[120].}
             #:changed "1.19" @elem{Added @racket['app-specific-password-dir].}]}

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

  @item{@racket[#:make _string] --- a @tt{make} command prefix to use
    on Unix and Mac OS clients, where the prefix is not quoted, so it
    can include space-separated arguments after the executable name;
    defaults to @racket["make"]
    @history[#:added "1.10"]}

  @item{@racket[#:j _integer] --- parallelism for @tt{make} on Unix
    and Mac OS and for @exec{raco setup} on all platforms; defaults
    to @racket[1]}

  @item{@racket[#:timeout _number] --- numbers of seconds to wait
    on a client before declaring failure; defaults to 30 minutes}

  @item{@racket[#:init _string-or-false] --- if non-@racket[#f], a
    command to run on a client and before any other commands; the
    default is @racket[#f]}

  @item{@racket[#:clean? _boolean] --- if true, then the build process
    on the client machine starts by removing @racket[#:dir]'s value;
    use @racket[#f] for a shared repo checkout; the default is
    determined by the @tt{CLEAN_MODE} makefile variable, unless
    @tech{local mode} is enabled, in which case
    the default is @racket[#f]}

  @item{@racket[#:pull? _boolean] --- if true, then the build process
    on the client machine starts by a @exec{git pull} in
    @racket[#:dir]'s value; use @racket[#f], for example, for a repo
    checkout that is shared with server; the default is @racket[#t],
    unless @tech{local mode} is enabled, in which case
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

  @item{@racket[#:static-libs? _boolean] --- if true, then create and
    include static libraries and associated files for embedding Racket
    in other applications, where supported; the default is @racket[#f]

    @history[#:added "1.7"]}

  @item{@racket[#:versionless? _boolean] --- if true, avoids including
    the Racket version number in an installer's name or in the
    installation path; the default is determined by the
    @tt{VERSIONLESS_MODE} makefile variable}

  @item{@racket[#:dist-base-version _string*] --- a version identifier
    to include in each installer's name just as the base name (as
    determined by @racket[#:dist-base]) and before the platform, as
    long as @racket[#:versionless?] is not specified as true; the
    default is @racket[(version)]

    @history[#:added "1.12"]}

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

  @item{@racket[#:log-file _string] --- the file name to use for the
    log file for the machine; defaults to @racket[#:name]'s value, but
    with ordering sequences (see @secref["name-format"]), @litchar{|},
    @litchar{;}, @litchar{!}, @litchar{*}, @litchar{(}, @litchar{)},
    @litchar{[}, and @litchar{]} removed, trailing and
    ending spaces removed, and remaining space sequences converted to
    @litchar{_}

    @history[#:added "1.8"
             #:changed "1.20" @elem{Changed default log name to remove
                                    noise and awkward characters.}]}

  @item{@racket[#:stream-log? _boolean] --- if true, send log output
    to server's output and error ports as well as logging them to a
    file; defaults to @racket[#f] @history[#:added "1.8"]}

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

  @item{@racket[#:current-link-version _string] --- substring of
    installer names to replace with @racket["current"] for ``current''
    links on a snapshot page; the default is the value of
    @racket[#:dist-base-version]

    @history[#:added "1.12"]}

  @item{@racket[#:pdf-doc? _boolean] --- whether to build PDF
    documentation when assembling a site; the default is @racket[#f]}

 @item{@racket[#:fake-installers? _boolean] --- if true, instead of
    using @tech{client machines} to build installers, just uses the
    content of the @filepath{README} file that would be included as
    the content of the installer file; beware that installer names are
    normally determined on the client side, so the server must guess
    about each installer name based on the @racket[#:name] description
    (e.g., ``Windows'' in the description implies a Windows
    installer); the default is @racket[#f] @history[#:added "1.11"]}

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
        @racket[#:smtp-user+password-file _path-string-or-false]
        @racket[#:smtp-sending-server _string*]
    --- configuration for sending e-mail through SMTP instead of
    @exec{sendmail}; the @racket[#:smtp-port] default (@racket[25],
    @racket[465], or @racket[587]) is picked based on
    @racket[#:smtp-connect], which can be @racket['plain],
    @racket['ssl], or @racket['tls] and defaults to @racket['plain];
    supply a non-@racket[#f] @racket[#:smtp-user] and
    @racket[#:smtp-password] or @racket[#:smtp-user+password-file]
    when authentication is required by the
    server, where a file is used by @racket[read]ing twice to get
    a default user and password value; supply @racket[#:smtp-sending-server] when the server
    needs a name other than @scheme["localhost"] for the sender

    @history[#:changed "1.16" @elem{Added @racket[#:smtp-user+password-file]
                                    and @racket[#:smtp-sending-server].}]}

  @item{@racket[#:site-help _hash-table] --- hash table of extra
    ``help'' information for entries on a web page created by the
    @tt{site} and @tt{snapshot-site} makefile targets; the hash keys
    are strings for row labels in the download table (after splitting
    on @litchar{|} and removing @litchar["{"]...@litchar["}"]), and
    the values are X-expressions (see @racketmodname[xml]) for the
    help content}

  @item{@racket[#:site-help-fallbacks _list] --- list of extra
    ``help'' information, like @racket[#:site-help], but with regexp
    keys instead of strings; each element of the list is a 2-element
    list containing a regexp and an X-expressions, and if no match is
    found already in @racket[#:site-help], the regexps are tried in
    order on row labels in the download table
    @history[#:added "1.11"]}

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

  @item{@racket[#:start-hook _proc] --- a procedure of one argument to
    be called once on the server before gathering packages, which can be
    useful for performing environment checks before proceeding; the procedure
    is called with the full site configuration; the default
    is @racket[void]

    @history[#:added "1.20"]}

]

Meta keyword:

@itemlist[

 @item{@racket[#:splice _hash-or-list] --- splices the content of a
    hash table or all contents of a list of hash tables into the enclosing
    @racket[machine], @racket[sequential], or @racket[parallel] form;
    each key must be supplied only once across the original arguments
    and the spliced tables

    @history[#:added "1.20"]}

]

}

@deftogether[(
@defproc[(spliceable ...) hash?]
)]{

 Returns the given keyword arguments in a hash table suitable for use
 with @racket[#:splice] in @racket[machine], @racket[sequential], or
 @racket[parallel].

 Calling @racket[spliceable] is almost the same as calling
 @racket[hasheq], except that keyword arguments are unquoted, and a
 syntax error is reported if a keyword appears multiple times.

}


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

@section[#:tag "Available Docker Images"]{Available Docker Images}

Several Docker images are available to build Racket distributions for
different platforms, especially for cross-compiling to different
operating systems and architectures. These images are available from
@hyperlink["https://hub.docker.com/r/racket/distro-build/tags"]{DockerHub}
as @filepath{racket/distro-build} plus a tag indicating the target platform.

To use one of these images, supply @racket[#:docker] to
@racket[machine] or similar functions as shown below. For cross-build
images, additional configuration arguments are needed as shown.
See @secref["docker-example"] for an example.

@version-guard{To use many of these images to build a set of distributions like the
ones on the main Racket download side, see
@racketmodname[distro-build/main-distribution].}

Unless otherwise noted, each image is available for two architectures:
@tt{linux/amd64} and @tt{linux/arm64} (i.e., to run on those hosts,
independent of the target machine in the case of cross-compilation).

@(define (dockerimage tag) @filepath{racket/distro-build:@tag})

@itemlist[

 @item{@dockerimage{latest}: A Debian 9 environment for creating a
 relatively generic Linux build, available for three architectures:
 @tt{linux/386}, @tt{linux/amd64}, and @tt{linux/arm64}.

 @racketblock[
  #:docker "racket/distro-build"
 ]

 The images are intended for a non-cross build from the perspective of
 the container, but using an image for an architecture other than the
 host's architecture cross-builds for the image's archiecture.

 The @dockerimage{i386-linux}, @dockerimage{x86_64-linux}, and
 @dockerimage{aarch64-linux} images are the same as
 @dockerimage{latest}, but specific to @tt{linux/386},
 @tt{linux/amd64}, or @tt{linux/arm64} (as opposed to a
 multi-architecture image). These tags can be useful in an environment
 where you want to specify an architecture other than the host's
 default and have multiple such images available.}


 @item{@dockerimage{debian10}: Like @dockerimage{latest}, but for
 Debian 10.

 @racketblock[
  #:docker "racket/distro-build:debian10"
 ]

 The @dockerimage{debian10-i386-linux}, @dockerimage{debian10-x86_64-linux}, and
 @dockerimage{debian10-aarch64-linux} images are the same as
 @dockerimage{debian10}, but specific to @tt{linux/386},
 @tt{linux/amd64}, or @tt{linux/arm64}. }


 @item{@dockerimage{crosslinux-i386}: For cross-building to Linux
 (Debian 10) for i386.

 @racketblock[
  #:docker "racket/distro-build:crosslinux-i386"
  #:cross-target-machine "ti3le"
  #:cross-target "i686-linux-gnu"
 ]}


 @item{@dockerimage{crosslinux-x86_64}: For cross-building to Linux
 (Debian 10) for x86_64.

 @racketblock[
  #:docker "racket/distro-build:crosslinux-x86_64"
  #:cross-target-machine "ta6le"
  #:cross-target "x86_64-linux-gnu"
 ]}


 @item{@dockerimage{crosslinux-aarch64}: For cross-building to Linux
 (Debian 10) for AArch64.

 @racketblock[
  #:docker "racket/distro-build:crosslinux-aarch64"
  #:cross-target-machine "tarm64le"
  #:cross-target "aarch64-linux-gnu"
 ]}


 @item{@dockerimage{crosslinux-arm}: For cross-building to Linux
 (Raspbian 10) for 32-bit ARMv6 VFP.

 @racketblock[
  #:docker "racket/distro-build:crosslinux-arm"
  #:cross-target-machine "tarm32le"
  #:cross-target "arm-linux-gnueabihf"
 ]}


 @item{@dockerimage{crosslinux-arm-debian7}: For cross-building to Linux
 (Raspbian 7) for 32-bit ARMv6 VFP. This image is available only for
 @tt{linux/amd64}.

 @racketblock[
  #:docker "racket/distro-build:crosslinux-arm-debian7"
  #:cross-target-machine "tarm32le"
  #:cross-target "arm-linux-gnueabihf"
 ]}


 @item{@dockerimage{crosslinux-riscv64}: For cross-building to Linux
 (Debian 12) for RISC-V (RV64G).

 @racketblock[
  #:docker "racket/distro-build:crosslinux-riscv64"
  #:cross-target-machine "trv64le"
  #:cross-target "riscv64-linux-gnu"
 ]}


 @item{@dockerimage{crosswin}: For cross-building Windows distributions,
 either 32-bit x86, 64-bit x64, or 64-bit Arm. Pick the specific Windows
 architecture through additional configuration as shown below.

 @racketblock[
  #:docker "racket/distro-build:crosswin"
  #:cross-target-machine "ti3nt"
  #:cross-target "i686-w64-mingw32"
 ]

 @racketblock[
  #:docker "racket/distro-build:crosswin"
  #:cross-target-machine "ta6nt"
  #:cross-target "x86_64-w64-mingw32"
  (code:comment "no `-g` to avoid compiler bug when building BC:")
  #:configure '("CFLAGS=-O2")
 ]

 @racketblock[
  #:docker "racket/distro-build:crosswin"
  #:cross-target-machine "tarm64nt"
  #:cross-target "aarch64-w64-mingw32"
 ]}


 @item{@dockerimage{osxcross-x86_64}: For cross-building Mac OS 10.9 (and up)
 distributions for 64-bit Intel.

 @racketblock[
  #:docker "racket/distro-build:osxcross-x86_64"
  #:cross-target-machine "ta6osx"
  #:cross-target "x86_64-apple-darwin13"
  #:configure '("CC=x86_64-apple-darwin13-cc")
  (code:comment "to enable code signing:")
  #:sign-cert-config (hash 'p12-dir @#,nonterm{path_to_files}
                           'p12-file @#,nonterm{cert_key_pair_filename}
                           'p12-password-file @#,nonterm{cert_key_pair_filename})
  (code:comment "to enable notarization:")
  #:notarization-config (hash 'app-specific-password-dir @#,nonterm{path_to_file}
                              'api-key-file @#,nonterm{api_key_filename})
 ]

 Beware that if @racket[#:sign-cert-config] or
 @racket[#:notarization-config] is added to a configuration, the
 Docker container will need to be recreated so that it mounts the
 relevant directories.}


 @item{@dockerimage{osxcross-aarch64}: For cross-building Mac OS 11 (and up)
 distributions for Apple Silicon.

 @racketblock[
  #:docker "racket/distro-build:osxcross-aarch64"
  #:cross-target-machine "tarm64osx"
  #:cross-target "aarch64-apple-darwin20.2"
  #:configure '("CC=aarch64-apple-darwin20.2-cc")
  (code:comment "to enable code signing:")
  #:sign-cert-config (hash 'p12-dir @#,nonterm{path_to_files}
                           'p12-file @#,nonterm{cert_key_pair_filename}
                           'p12-password-file @#,nonterm{cert_key_pair_filename})
  (code:comment "to enable notarization:")
  #:notarization-config (hash 'app-specific-password-dir @#,nonterm{path_to_file}
                              'api-key-file @#,nonterm{api_key_filename})
 ]

 Beware that if @racket[#:sign-cert-config] or
 @racket[#:notarization-config] is added to a configuration, the
 Docker container will need to be recreated so that it mounts the
 relevant directories.}


 @item{@dockerimage{osxcross-i386}: For cross-building Mac OS 10.6 (and up)
 distributions for 32-bit Intel.

 @racketblock[
  #:docker "racket/distro-build:osxcross-i386"
  #:cross-target-machine "ti3osx"
  #:cross-target "i386-apple-darwin10"
  #:configure '("CC=i386-apple-darwin10-cc"
                (code:comment "FIXME: needed when host is x86_64:")
                "--build=x86_64-pc-linux-gnu"
                (code:comment "recommended for a smaller distribution:")
                "--disable-embedfw")
 ]}


 @item{@dockerimage{osxcross-ppc}: For cross-building Mac OS 10.5 (and up)
 distributions for 32-bit PowerPC.

 @racketblock[
  #:docker "racket/distro-build:osxcross-ppc"
  #:cross-target-machine "tppc32osx"
  #:cross-target "powerpc-apple-darwin9"
  (code:comment "recommended for a smaller distribution:")
  #:configure '("--disable-embedfw")
 ]}

]


@version-guard{

@; ----------------------------------------

@section[#:tag "main-distribution"]{Main Distribution via Docker}

@defmodule[distro-build/main-distribution]

The @racketmodname[distro-build/main-distribution] library provides
functions for generating a site configuration that builds
distributions like those available at the main Racket download site.

The configuration assumes a x86_64 (64-bit Intel) or AArch64 (64-bit
Arm) host that can run Docker containers. See
@racket[make-spliceable-limits] for information on expected resource
usage.

@defproc[(make-machines [#:minimal? minimal? any/c #f]
                        [#:pkgs pkgs (listof string?) (if minimal?
                                                          '()
                                                          '("main-distribution"))]
                        [#:filter-rx filter-rx (or/c #f regexp?) #f]
                        [#:installer? installer? any/c #t]
                        [#:tgz? tgz? any/c minimal?]
                        [#:name name string? (if minimal?
                                                 minimal-racket-name
                                                 racket-name)]
                        [#:file-name file-name string? (if minimal?
                                                           minimal-racket-file-name
                                                           racket-file-name)]
                        [#:container-prefix container-prefix string? "main-dist-"]
                        [#:cs? cs? any/c #t]
                        [#:bc? bc? any/c #f]
                        [#:cs-name-suffix cs-name-suffix string? ""]
                        [#:bc-name-suffix bc-name-suffix string? " BC"]
                        [#:uncommon? uncommon? any/c minimal?]
                        [#:extra-linux-variants? extra-linux-variants? any/c #t]
                        [#:windows-sign-post-process windows-sign-post-process (or/c #f (listof string?)) #f]
                        [#:mac-sign-cert-config mac-sign-cert-config (or/c #f hash?) #f]
                        [#:mac-notarization-config mac-notarization-config (or/c #f hash?) #f]
                        [#:recompile-cache recompile-cache (or/c symbol? #f) 'main-dist]
                        [#:aliases aliases list? '()])
          site-config?]{

Generates a @racket[parallel] set of @racket[machine] configurations,
each using Docker (see @secref["Available Docker Images"]), for
generating a site configuration that builds distributions like those
available at the main Racket download site. The result is intended as
an argument to a top-level @racket[sequential] to further configure
the build, especially with a @racket[#:splice]s result from
@racket[make-spliceable-limits] to configure a timeout and to control
the number of Docker containers that run concurrently.

The @racket[minimal?] argument indicates whether the configuration is
intended as a Minimal Racket distribution. It determines the default
for many other arguments. If @racket[minimal?] is true, then
@racket[pkgs] must be an empty list.

To fully imitate the main download site, @racket[make-machines] should
be called twice, once with @racket[minimal?] as true and once with
@racket[minimal?] as false, normally in that order. Results from
multiple calls must be combined with @racket[sequential], not
@racket[parallel], because containers are reused to reduce unnecessary
rebuilds. When using @racket[#:clean?], a good strategy is to wrap the
result of @racket[make-machine] with @racket[minimal?] as true also
with @racket[#:clean?] as true, and not the result of
@racket[make-machine] with @racket[minimal?] as @racket[#false]; see
also @racket[extract-container-names]. Supply
@racket[mac-sign-cert-config], @racket[mac-notarization-config], and
@racket[recompile-cache] arguments consistently, and beware that
changing those arguments may require removing old containers.

The @racket[pkgs] argument determines packages that are pre-installed
in the distribution. It must be a subset of the packages that are
listed for @racket[#:pkgs] in the top-level site configuration.

The @racket[filter-rx] argument, when not @racket[#f], determines
which installers are generated. It is matched against the human-readable
@racket[#:name] for each configuration, so it will be something like

@centerline{@litchar{{1} Racket | {3} Linux | {1} 64-bit x86_64; built on Debian 10}}

If @racket[installer?] is true, then the configurations will include
@filepath{.exe} installers for Windows, @filepath{.dmg} disk images
for Mac PS, and @filepath{.sh} installers for Linux. If @racket[tgz?]
is true, then the configurations will include @filepath{.tgz} archives
for all platforms. Source distributions will be included as
@filepath{.tgz} archives independent of @racket[installer?] and
@racket[tgz?].

The @racket[name] argument provides a component of the human-readable
@racket[#:name] for a configuration, typically @racket["{1} Racket"]
or @racket["{2} Minimal Racket"]. The @racket[file-name] argument
provides the component of an installer or archive name, typically
@racket["racket"] or @racket["racket-minimal"].

The @racket[container-prefix] argument is used as a prefix on all
Docker container names used by the build.

The @racket[cs?] and @racket[bc?] arguments indicate whether the
respective Racket variant is included, and the @racket[cs-name-suffix]
and @racket[bc-name-suffix] arguments provide a suffix to add to
@racket[name].

The @racket[uncommon?] argument indicates whether to include platforms
that are supported but not among the most widely used, and that are
included only in Minimal Racket form at the main Racket download site.

The @racket[extra-linux-variants?] argument indicates whether to
include extra Linux variants. The base variant links to libraries to
work on as many Linux distributions as possible, but additional
variants can provide a better fit for the C and terminal libraries on
different Linux distributions.

If @racket[windows-sign-post-process] is not @racket[#f], then it is
used as a @racket[#:server-installer-post-process] for Windows
installer configurations to sign them. Similarly, if
@racket[mac-sign-cert-config] or @racket[mac-notarization-config]is
not @racket[#f], it is used as a @racket[#:sign-cert-config] or
@racket[#:notarization-config]value to sign Mac OS disk images.

The @racket[recompile-cache] argument is used as the
@racket[#:recompile-cache] configuration for all installer builds.

The @racket[aliases] list is added to @racket[#:dist-alises] for each
configuration.

}

@defproc[(make-spliceable-limits [#:max-parallel max-parallel exact-positive-integer? 3]
                                 [#:j j exact-positive-integer? 2]
                                 [#:timeout timeout real? (* #e1.5 60 60)])
         hash?]{

 Passes along all arguments to @racket[spliceable], effectively
 providing good defaults for a main-distribution build in combination
 with the results of @racket[make-machines].

 The @racket[max-parallel] argument limits the number of Docker
 containers that run concurrently, while @racket[j] limits parallelism
 within a Docker container.

 Expect each container to use 2 GB of memory or @racket[j] GB,
 whichever is larger. Containers are not automatically removed after a
 build, so they are available for incremental builds; see also
 @racket[extract-container-names]. Expect the full set of containers
 to use up to 128 GB of disk space. Note that Docker on some host
 platforms (such as Mac OS) has a configurable set of limits that span
 all running containers, so make sure those limits are set
 appropriately.

}

@deftogether[(
@defproc[(make-start-check) (procedure-arity-includes/c 1)]
@defproc[(make-site-help) hash?]
@defproc[(make-site-help-fallbacks) list?]
)]{

 Returns useful defaults for @racket[#:start-check],
 @racket[#:site-help], and @racket[#:site-help-fallback] top-level
 configuration.

}

@deftogether[(
@defthing[racket-name string?]
@defthing[minimal-racket-name string?]
@defthing[racket-file-name string?]
@defthing[minimal-racket-file-name string?]
)]{

 Default strings for names and file names.

}

@defproc[(extract-container-names [config site-config?])
         (listof string?)]{

 Extracts all Docker container names used to build @racket[config].

 Docker containers are left in place after a distribution build, which
 enables incremental updates (to some degree) when rebuilding. It's
 always safe to discard the containers between builds.

 Note that the configuration produced by @racket[make-machines]
 creates Git checkouts in the @filepath{build} subdirectory of the
 Racket checkout used to drive a distribution build. To reset a build
 to work from scratch, be sure to delete the @filepath{build}
 subdirectory as well as removing Docker containers.

}

}

@; ----------------------------------------

@section{Examples}

Here are some example configuration files.

@subsection[#:tag "single-installer"]{Single Installer}

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

Beware that the default configuration creates a relatively large
distribution, because it contains @filepath{main-distribution} and
@filepath{main-distribution-test}. Also, the default configuration
uses a single sequential job for the client phase, instead of
parallelizing. Consider providing @racket[#:pkgs] and/or
@racket[#:j] options to @racket[machine].

While the client part of this build is running, output is written to
@filepath{build/log/localhost} (since @racket[#:name] defaults to
@racket[#:host], and @racket[#:host] defaults to @racket["localhost"]).

@subsection[#:tag "docker-example"]{Cross-Build via Docker}

To build for Mac OS on a host machine that can run Docker containers
(see @secref["Available Docker Images"]), create a @filepath{build/site.rkt}
file with

@codeblock{
  #lang distro-build/config

  (machine
   ;; FIXME: the name of the container to be created for building
   #:host "example-osxcross-aarch64"
   ;; Image name
   #:docker "racket/distro-build:osxcross-aarch64"
   ;; Cross-compile configuration
   #:cross-target-machine "tarm64osx"
   #:cross-target "aarch64-apple-darwin20.2"
   #:configure '("CC=aarch64-apple-darwin20.2-cc"))
}

The container name provided as @racket[#:host] enables using the same
container for incremental rebuilds, instead of starting from scratch
each time.

See @secref["single-installer"] for advice about providing
@racket[#:pkgs] and @racket[#:j] options. Depending on the
distribution, a @racket[#:timeout] larger than the default of
@racket[(* 60 30)] seconds may also be needed, since cross compilation
is much more work for a client.

While the client part of this build is running, output is written to
@filepath{build/log/example-osxcross-aarch64} (since @racket[#:name]
defaults to @racket[#:host]).

@subsection{Multiple Platforms}

A configuration module that drives multiple Docker containers in
parallel to build for both 64-bit Windows (x64) and Mac OS (Intel)
might look like this:

@codeblock{
    #lang distro-build/config

    (sequential
     ;; Minimal Racket:
     #:pkgs '()
     ;; Up to 2 jobs in each of 2 containers:
     #:j 2
     (parallel ; could replace with `sequential`
       (machine
        #:name "Windows (64-bit x64)"
        #:host "example-windows-x86_64" ; FIXME: container name
        #:docker "racket/distro-build:crosswin"
        #:cross-target-machine "ta6nt"
        #:cross-target "x86_64-w64-mingw32")
       (machine
        #:name "Mac OS (64-bit Intel)"
        #:host "example-macosx-x86_64" ; FIXME: container name
        #:docker "racket/distro-build:osxcross-x86_64"
        #:cross-target-machine "ta6osx"
        #:cross-target "x86_64-apple-darwin13"
        #:configure '("CC=x86_64-apple-darwin13-cc"))))
}

With this configuration file in @filepath{site.rkt},

@commandline{make installers CONFIG=site.rkt}

produces two installers, both in @filepath{build/installers}, and a
hash table in @filepath{table.rktd} that maps
@racket["Windows (64-bit x64)"] to the Windows installer
and @racket["Mac OS (64-bit Intel)"] to the Mac OS installer.

While the client parts of this build are running, output is written to
@filepath{build/log/Windows (64-bit x64)} and
@filepath{build/log/Mac OS (64-bit Intel)}.


@subsection{Installer Web Page}

To make a web page that serves both a minimal installer and
main-installation packages, create a @filepath{site.rkt} file with

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

@subsection[#:tag "main-distro-example"]{Main Download Site}

A configuration module that drives a build like the main Racket
download page (which will take hours) might look like this:

@codeblock{
  #lang distro-build/config
  (require distro-build/main-distribution)

  (sequential
    ;; FIXME: the URL where the installer and packages will be:
    #:dist-base-url (string-append "http://my-server.domain/snapshots/"
                                   (current-stamp) "/")
    #:splice (make-spliceable-limits)
    (make-machines #:minimal? #t)
    (make-machines))
}


@subsection{Multiple Platforms on Multiple Machines}

A configuration module that drives multiple client machines---virtual
and remote---to build installers might look like this:

@codeblock{
    #lang distro-build/config

    (sequential
     #:pkgs '("drracket")
     #:server-hosts '() ; Insecure? See below.
     (machine
      #:name "Linux (32-bit, Precise Pangolin)"
      #:vbox "Ubuntu 12.04"
      #:host "192.168.56.102")
     (machine
      #:name "Windows (64-bit)"
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
