# @summary Default configuration paths for Apt.
#
# @param sources_list_d
#   Default path for Apt source list files.
#
# @param conf_d
#   Default path for Apt configuration files.
#
# @param preferences_d
#   Default path for Apt preferences files.
#
# @param config_files
#   Configuration directories and file extensions used by `apt::setting`.
#
class apt::params {
  $root           = '/etc/apt'
  $sources_list_d = "${root}/sources.list.d"
  $conf_d         = "${root}/apt.conf.d"
  $preferences_d  = "${root}/preferences.d"

  $config_files = {
    'conf'    => {
      'path' => $conf_d,
      'ext'  => '',
    },
    'pref'    => {
      'path' => $preferences_d,
      'ext'  => '.pref',
    },
    'list'    => {
      'path' => $sources_list_d,
      'ext'  => '.list',
    },
    'sources' => {
      'path' => $sources_list_d,
      'ext'  => '.sources',
    },
  }
}
