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

  # Pull in global version from Hiera
  $ruby_version = hiera('ruby::global::version')
  ruby::version { $ruby_version: }
  # This sets our default in rbenv and installs it if needed
  class { 'ruby::global':
    version => $ruby_version
  }

  # Pull in hieradata to create most of our Ruby packages
  $ruby_packages = hiera_hash('ruby_packages')
  create_resources('ruby_gem', $ruby_packages)

  # puppet-ruby breaks some gems, this is my silly work around..
  exec { "bundle config charlock_holmes for ${ruby_version}":
    command => "bundle config build.charlock_holmes --with-icu-dir=${boxen::config::homebrewdir}/opt/icu4c",
    onlyif  => 'bundle config build.charlock_holmes | grep -q "You have not"',
  }

  exec { "charlock_holmes for ${ruby_version}":
    command => "env -i SHELL=/bin/zsh zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install charlock_holmes'",
    unless  => "env -i SHELL=/bin/zsh zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list charlock_holmes | grep charlock_holmes'",
    require => Exec["bundle config charlock_holmes for ${ruby_version}"],
  }

  exec { "bundle config nokogiri for ${ruby_version}":
    command => "bundle config build.nokogiri --use-system-libraries --with-xml2-include=${boxen::config::homebrewdir}/opt/libxml2/include/libxml2",
    onlyif  => 'bundle config build.nokogiri | grep -q "You have not"',
  }

  exec { "nokogiri for ${ruby_version}":
    command => "env -i SHELL=/bin/zsh zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install nokogiri -- --with-iconv-lib=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/lib --with-iconv-include=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/include'",
    unless  => "env -i SHELL=/bin/zsh zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list nokogiri | grep nokogiri'",
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

  # Pull the version number of our global python from hiera
  # Add any other pythons under this
  $python_version = hiera('python::global')

  # This does the actual install
  python::version { $python_version: }

  # This sets the version that pyenv uses everywhere to our version
  class { 'python::global':
    version => $python_version,
  }

  # Install Python 3 for Cortex
  python::version { '3.4.2': }
  python::local { "${home}/reops/cortex":
    version => '3.4.2'
  }

  # Required before Ansible will install
  file { '/usr/share/ansible':
    ensure => directory,
    owner  => $boxen_user,
    group  => staff,
  }

  # Pull in hieradata to create all our Python packages
  $python_packages = hiera_hash('python_packages')
  create_resources('python::package', $python_packages)

  # cx-Oracle requires a bunch of crap first, this will break for anyone else
  # Need these values in the shell
  #   LD_LIBRARY_PATH=:/Users/kholloway/lib/oracle/instantclient_11_2
  #   ORACLE_HOME=/Users/kholloway/lib/oracle/instantclient_11_2
  # Need instantclient basic and instantclient sdk in the directories above
  #
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
      'pstree',
      'postgresql',
      'gsasl',
      'curl',
      'wget',
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

  # Install our brewcask packages
  package { $brewcask_packages:
    provider => 'brewcask',
  }

  # Example of how to download and unarchive a zip file
  #archive { 'service-open-in-safari':
  #  ensure     => present,
  #  url        => 'http://www.gingerbeardman.com/services/open-current-safari-page-in-google-chrome.zip',
  #  target     => "/Users/${luser}/Library/Services/",
  #  extension  => 'zip',
  #  checksum   => false,
  #  src_target => '/tmp',
  #}

  file { "${boxen::config::srcdir}/our-boxen":
    ensure => link,
    target => $boxen::config::repodir
  }
}
