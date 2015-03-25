class people::kholloway {
  # Set home dir for later use
  $home = "/Users/${::boxen_user}"

  # Path for my local repos
  $my_repos = "${home}/repos"

  # Get the Xcode path to include files
  $include_path = inline_template('<%= %x{xcrun --show-sdk-path}.strip %>')

  # Link the Xcode include path to /usr/include to fix a lot of errors from happening
  # during ruby and python modules build time
  file { '/usr/include':
    ensure => link,
    target => "${include_path}/usr/include",
  }

  # Create environment setup for Brewcask to fix default installs into /usr/local/bin which no longer exists
  # NOTE: This env var seems to be ignored during the brewcask installs inside of boxen but fixes
  #       cask doing the wrong thing when using it via the CLI
  #       To fix it for boxen installs see the brewcask package definition near the bottom
  #       where I define the same binarydir install option
  boxen::env_script { 'homebrewcask':
    content => "export HOMEBREW_CASK_OPTS=\"--binarydir=${boxen::config::homebrewdir}/bin\"",
  }

  # OS X Settings
  include people::kholloway::osx

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

  # Install Python 3
  python::version { '3.4.2': }

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

  # Brew tap neovim, do it this way because the tap name is different from the
  # name that you call it by resulting in Boxen/Puppet tap'ing it each run..
  exec { 'tap-homebrew-neovim':
    command => 'brew tap neovim/homebrew-neovim',
    creates => "${homebrew::config::tapsdir}/neovim/homebrew-neovim",
  }

  # Now install Neovim
  package { 'neovim':
    ensure          => present,
    install_options => ['--HEAD'],
    require         => Exec['tap-homebrew-neovim'],
  }

  # Bitbucket repo that has my RC files
  repository { 'myconfigs':
    source => 'git@bitbucket.org:kholloway1/myconfigs.git',
    path   => "${my_repos}/myconfigs",
  }

  # RC Files from myconfigs repo
  file { "${home}/.vimrc":
    ensure  => link,
    target  => "${my_repos}/myconfigs/vimrc",
    require => Repository['myconfigs'],
  }

  # .vim dirs
  file { "${home}/.vim":
    ensure  => directory,
  }
  file { "${home}/.vim/bundle":
    ensure  => directory,
    require => File["${home}/.vim"],
  }
  file { "${home}/.vim/_backup":
    ensure  => directory,
    require => File["${home}/.vim"],
  }
  file { "${home}/.vim/_temp":
    ensure  => directory,
    require => File["${home}/.vim"],
  }

  exec { "Install_Vundle":
    command => "git clone https://github.com/gmarik/Vundle.vim.git ${home}/.vim/bundle/Vundle.vim",
    creates => "${home}/.vim/bundle/Vundle.vim/CONTRIBUTING.md",
    require => [
      File["${home}/.vim"],
      File["${home}/.vimrc"],
    ]
  }

  # Install Vundle packages inside Vim
  exec { "Install_Update_Vundle_Packages":
    command     => "vim +PluginInstall! +qall",
    environment => "HOME=${home}",
    require     => Exec["Install_Vundle"],
  }

  # common, useful packages via Homebrew
  $brew_packages = [
      'icu4c',
      'coreutils',
      'libxml2',
      'keychain',
      'ctags',
      'boot2docker',
      'pstree',
      'postgresql',
      'gsasl',
      'the_silver_searcher',
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
      'tmux',
      'lynx',
      'zsh',
      'tig'
  ]

  # Install the above packages using the default provider which is homebrew
  package { $brew_packages: }

  $brewcask_packages = [
    'iterm2',
    'mou',
    'qlmarkdown',
    'vagrant',
    'chefdk',
    'atom',
    'filebot',
    'macpass',
    'licecap',
    'sourcetree',
    'chicken'
  ]

  # Install our brewcask packages
  package { $brewcask_packages:
    provider        => 'brewcask',
    install_options => ["--binarydir=${boxen::config::homebrewdir}/bin"],
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

  # Increase memory limits on OSX NOTE: this requires a reboot..
  property_list_key { 'maxfiles1':
    ensure => present,
    path   => '/Library/LaunchDaemons/limit.maxfiles.plist',
    key    => 'Label',
    value  => 'limit.maxfiles',
  }
  property_list_key { 'maxfiles2':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxfiles.plist',
    key        => 'ProgramArguments',
    value      => ['launchctl','limit','maxfiles','65536','65536'],
    value_type => 'array',
    require    => Property_List_Key['maxfiles1'],
  }
  property_list_key { 'maxfiles3':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxfiles.plist',
    key        => 'RunAtLoad',
    value      => true,
    value_type => 'boolean',
    require    => Property_List_Key['maxfiles2'],
  }
  property_list_key { 'maxfiles4':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxfiles.plist',
    key        => 'ServiceIPC',
    value      => false,
    value_type => 'boolean',
    require    => Property_List_Key['maxfiles3'],
  }

  # Increase MaxProc
  property_list_key { 'maxproc1':
    ensure => present,
    path   => '/Library/LaunchDaemons/limit.maxproc.plist',
    key    => 'Label',
    value  => 'limit.maxproc',
  }
  property_list_key { 'maxproc2':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxproc.plist',
    key        => 'ProgramArguments',
    value      => ['launchctl','limit','maxproc','2048','2048'],
    value_type => 'array',
    require    => Property_List_Key['maxproc1'],
  }
  property_list_key { 'maxproc3':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxproc.plist',
    key        => 'RunAtLoad',
    value      => true,
    value_type => 'boolean',
    require    => Property_List_Key['maxproc2'],
  }
  property_list_key { 'maxproc4':
    ensure     => present,
    path       => '/Library/LaunchDaemons/limit.maxproc.plist',
    key        => 'ServiceIPC',
    value      => false,
    value_type => 'boolean',
    require    => Property_List_Key['maxproc3'],
    notify     => Notify['reboot_me'],
  }

  notify {'reboot_me':
    name => 'Reboot required for maxproc and maxfiles settings',
  }

}
