require boxen::environment
require homebrew
require gcc

Exec {
  group       => 'staff',
  logoutput   => on_failure,
  user        => $boxen_user,

  path => [
    "${boxen::config::home}/rbenv/shims",
    "${boxen::config::home}/rbenv/bin",
    "${boxen::config::home}/rbenv/plugins/ruby-build/bin",
    "${boxen::config::home}/homebrew/bin",
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin'
  ],

  environment => [
    "HOMEBREW_CACHE=${homebrew::config::cachedir}",
    "HOME=/Users/${::boxen_user}"
  ]
}

File {
  group => 'staff',
  owner => $boxen_user
}

Package {
  provider => homebrew,
  require  => Class['homebrew']
}

Repository {
  provider => git,
  extra    => [
    '--recurse-submodules'
  ],
  require  => File["${boxen::config::bindir}/boxen-git-credential"],
  config   => {
    'credential.helper' => "${boxen::config::bindir}/boxen-git-credential"
  }
}

Service {
  provider => ghlaunchd
}

Homebrew::Formula <| |> -> Package <| |>

node default {
  # core modules, needed for most things
  include dnsmasq
  include git
  include hub
  include nginx
  include brewcask

  # Disabled for now because of issues with FileVault and Yosemite (hang on reboot)
  # fail if FDE is not enabled
  # if $::root_encrypted == 'no' {
  #  fail('Please enable full disk encryption and try again')
  #}

  # node versions
  #include nodejs::v0_6
  #include nodejs::v0_8
  include nodejs::v0_10

  # default ruby versions
  #ruby::version { '1.9.3': }
  #ruby::version { '2.0.0': }
  #ruby::version { '2.1.0': }
  #ruby::version { '2.1.1': }

  # Get the Xcode path to include files
  $include_path = inline_template('<%= %x{xcrun --show-sdk-path}.strip %>')

  # Link the Xcode include path to /usr/include to fix a lot of errors from happening
  # during ruby and python modules build time
  file { '/usr/include':
    ensure => link,
    target => "${include_path}/usr/include",
  }

  # Set our new Ruby version
  # NOTE: You can also specify versions to install as shown a few lines above
  # See the Puppet-ruby module on Github for more info:
  #  https://github.com/boxen/puppet-ruby

  $ruby_version = '2.1.2'
  ruby::version { $ruby_version: }

  # This sets our default in rbenv
  class { 'ruby::global':
    version => $ruby_version
  }

  ruby_gem { 'bundler for all rubies':
    gem          => 'bundler',
    version      => '~> 1.0',
    ruby_version => '*',
  }
  ruby_gem { "puppet for ${ruby_version}":
    gem          => 'puppet',
    version      => '~> 3.4.0',
    ruby_version => $ruby_version,
  }
  ruby_gem { "facter for ${ruby_version}":
    gem          => 'facter',
    version      => '~> 1.7.6',
    ruby_version => $ruby_version,
  }
  ruby_gem { "puppet-lint for ${ruby_version}":
    gem          => 'puppet-lint',
    version      => '~> 1.0.1',
    ruby_version => $ruby_version,
  }
  ruby_gem { "puppet-syntax for ${ruby_version}":
    gem          => 'puppet-syntax',
    version      => '~> 1.3.0',
    ruby_version => $ruby_version,
  }

  # puppet-ruby breaks some gems, this is my silly work around..
  exec { "bundle config charlock_holmes for ${ruby_version}":
    command => "bundle config build.charlock_holmes --with-icu-dir=${boxen::config::homebrewdir}/opt/icu4c",
    onlyif  => 'bundle config build.charlock_holmes | grep -q "You have not"',
  }

  exec { "charlock_holmes for ${ruby_version}":
    command => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install charlock_holmes'",
    unless  => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list charlock_holmes | grep charlock_holmes'",
    require => Exec["bundle config charlock_holmes for ${ruby_version}"],
  }

  exec { "bundle config nokogiri for ${ruby_version}":
    command => "bundle config build.nokogiri --use-system-libraries --with-xml2-include=${boxen::config::homebrewdir}/opt/libxml2/include/libxml2",
    onlyif  => 'bundle config build.nokogiri | grep -q "You have not"',
  }

  exec { "nokogiri for ${ruby_version}":
    command => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install nokogiri -- --with-iconv-lib=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/lib --with-iconv-include=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/include'",
    unless  => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list nokogiri | grep nokogiri'",
    require => [
      Package['libxml2'],
      Exec["bundle config nokogiri for ${ruby_version}"],
    ],
  }

  # Gollum requires some stuff first..
  ruby_gem { "gollum for ${ruby_version}":
    gem          => 'gollum',
    version      => '~> 3.0.0',
    ruby_version => $ruby_version,
    require      => [
      Package['icu4c'],
      Exec["charlock_holmes for ${ruby_version}"],
      Exec["nokogiri for ${ruby_version}"],
    ],
  }

  # Oddball setup for Python on 10.9 and 10.10
  $python_version = '2.7.8'
  exec { "python ${python_version}":
    command => "env -i bash -c 'source /opt/boxen/env.sh && CFLAGS=\"-I$(xcrun --show-sdk-path)/usr/include\" pyenv install ${python_version}'",
    creates => "/opt/boxen/pyenv/versions/${python_version}/bin/python",
  }

  # Normally this does the actual install but due to a bug the exec above is required
  python::version { $python_version: }

  # Set pyenv_version in Hiera /opt/boxen/repo/hiera/common.yaml like the line below
  #  python::pyenv_version: "v20141012"

  # This sets the version that pyenv uses everywhere to our version
  class { 'python::global':
    version => $python_version,
  }

  python::package { "fabric for ${python_version}":
    package => 'fabric',
    python  => $python_version,
    version => '>=1.9.1',
  }
  python::package { "markdown for ${python_version}":
    package => 'markdown',
    python  => $python_version,
    version => '>=2.4.1',
  }
  python::package { "mako for ${python_version}":
    package => 'mako',
    python  => $python_version,
    version => '>=1.0.0',
  }
  python::package { "bottle for ${python_version}":
    package => 'bottle',
    python  => $python_version,
    version => '>=0.12.7',
  }
  python::package { "SQLAlchemy for ${python_version}":
    package => 'sqlalchemy',
    python  => $python_version,
    version => '>=0.9.7',
  }
  python::package { "ansible for ${python_version}":
    package => 'ansible',
    python  => $python_version,
    version => '>=1.7.2',
  }
  python::package { "pssh for ${python_version}":
    package => 'pssh',
    python  => $python_version,
    version => '>=2.3.1',
  }
  python::package { "requests for ${python_version}":
    package => 'requests',
    python  => $python_version,
    version => '>=1.0.4',
  }
  python::package { "suds for ${python_version}":
    package => 'suds',
    python  => $python_version,
    version => '>=0.4',
  }
  python::package { "sqlsoup for ${python_version}":
    package => 'sqlsoup',
    python  => $python_version,
    version => '>=0.9.0',
  }
  python::package { "pyzmq for ${python_version}":
    package => 'pyzmq',
    python  => $python_version,
    version => '>=14.3.1',
  }
  python::package { "psycopg2 for ${python_version}":
    package => 'psycopg2',
    python  => $python_version,
    version => '>=2.5.3',
  }
  python::package { "Sphinx for ${python_version}":
    package => 'sphinx',
    python  => $python_version,
    version => '>=1.2.2',
  }
  python::package { "awscli for ${python_version}":
    package => 'awscli',
    python  => $python_version,
    version => '>=1.4.2',
  }
  python::package { "dnspython for ${python_version}":
    package => 'dnspython',
    python  => $python_version,
    version => '>=1.11.1',
  }
  python::package { "luigi for ${python_version}":
    package => 'luigi',
    python  => $python_version,
    version => '>=1.0.16',
  }
  python::package { "pytz for ${python_version}":
    package => 'pytz',
    python  => $python_version,
    version => '>=2014.4',
  }
  python::package { "python-ldap for ${python_version}":
    package => 'python-ldap',
    python  => $python_version,
    version => '>=2.4.18',
  }

  # cx-Oracle requires a bunch of crap first, this will break for anyone else
  # Need these values in the shell
  #   LD_LIBRARY_PATH=:/Users/kholloway/lib/oracle/instantclient_11_2
  #   ORACLE_HOME=/Users/kholloway/lib/oracle/instantclient_11_2
  python::package { "cx-Oracle for ${python_version}":
    package => 'cx-oracle',
    python  => $python_version,
    version => '>=5.1.3',
  }

  # common, useful packages via Homebrew
  $brew_packages = [
      'ack',
      'icu4c',
      'findutils',
      'coreutils',
      'libxml2',
      'keychain',
      'boot2docker',
      'postgresql',
      'gsasl',
      'curl',
      'iftop',
      'tree',
      'go',
      'htop-osx',
      'jq',
      'multimarkdown',
      'nmap',
      'mercurial',
      'lynx',
      'zsh',
      'gnu-tar'
  ]

  # Install the above packages using the default provider which is homebrew
  package { $brew_packages: }

  $brewcask_packages = [
    'iterm2',
    'mou',
    'qlmarkdown',
    'vagrant',
    'chicken'
  ]

  package { $brewcask_packages:
    provider => 'brewcask',
  }

  file { "${boxen::config::srcdir}/our-boxen":
    ensure => link,
    target => $boxen::config::repodir
  }
}
