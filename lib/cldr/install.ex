defmodule Cldr.Install do
  @moduledoc """
  Provides functions for installing locales.

  When installed as a package on from [hex](http://hex.pm), `Cldr` has only
  the default locales `["en", "root"]` installed and configured.

  When other locales are added to the configuration `Cldr` will attempt to
  download the locale from [github](https://github.com/kipcole9/cldr)
  during compilation.

  If `Cldr` is installed from github directly then all locales are already
  installed.
  """

  import Cldr.Macros, only: [docp: 1]
  defdelegate client_data_dir(), to: Cldr.Config
  defdelegate client_locales_dir(), to: Cldr.Config
  defdelegate locale_filename(locale), to: Cldr.Config

  @doc """
  Install all the configured locales.
  """
  def install_requested_locales do
    Enum.each Cldr.Config.requested_locales(), &install_locale/1
    :ok
  end

  @doc """
  Install all available locales.
  """
  def install_all_locales do
    Enum.each Cldr.all_locales(), &install_locale/1
    :ok
  end

  @doc """
  Download the requested locale from github into the
  client application's cldr data directory.

  * `locale` is any locale returned by `Cldr.known_locales{}`

  * `options` is a keyword list.  Currently the only supported
  option is `:force` which defaults to `false`.  If `truthy` the
  locale will be installed or re-installed.

  The data directory is typically `./priv/cldr/locales`.

  This function is intended to be invoked during application
  compilation when a valid locale is configured but is not yet
  installed in the application.

  An https request to the master github repository for `Cldr` is made
  to download the correct version of the locale file which is then
  written to the configured data directory.
  """
  def install_locale(locale, options \\ []) do
    if !locale_installed?(locale) or options[:force] do
      ensure_client_dirs_exist!(client_locales_dir())
      Application.ensure_started(:inets)
      Application.ensure_started(:ssl)
      do_install_locale(locale, locale in Cldr.Config.all_locales())
    else
      :already_installed
    end
  end

  # Normally a library function shouldn't raise an exception (thats up
  # to the client app) but we install locales only at compilation time
  # and an exception then is the appropriate response.
  defp do_install_locale(locale, false) do
    raise Cldr.UnknownLocaleError,
      "Failed to install the locale #{inspect locale}. The locale is not known."
  end

  defp do_install_locale(locale, true) do
    require Logger

    url = "#{base_url()}#{locale_filename(locale)}" |> String.to_charlist

    output_file_name = [client_locales_dir(), "/", locale_filename(locale)]
    |> :erlang.iolist_to_binary

    case :httpc.request(url) do
      {:ok, {{_version, 200, 'OK'}, _headers, body}} ->
        output_file_name
        |> File.write!(:erlang.list_to_binary(body))

        Logger.info "Downloaded locale #{inspect locale}"
        {:ok, output_file_name}
      {_, {{_version, code, message}, _headers, _body}} ->
        Logger.error "Failed to download locale #{inspect locale} from #{url}. " <>
          "HTTP Error: (#{code}) #{inspect message}"
        {:error, code}
      {:error, {:failed_connect, [{_, {host, _port}}, {_, _, sys_message}]}} ->
        Logger.error "Failed to connect to #{inspect host} to download " <>
          "locale #{inspect locale}. Reason: #{inspect sys_message}"
        {:error, sys_message}
    end
  end

  docp """
  Builds the base url to retrieve a locale file from github.

  The url is built using the version number of the `Cldr` application.
  If the version is a `-dev` version then the locale file is downloaded
  from the master branch.

  This requires that a branch is tagged with the version number before creating
  a release or publishing to hex.
  """
  @base_url "https://raw.githubusercontent.com/kipcole9/cldr/"
  defp base_url do
    [@base_url, branch_from_version(), "/priv/cldr/locales/"]
    |> :erlang.iolist_to_binary
  end

  # Returns the version of ex_cldr
  defp app_version do
    cond do
      spec = Application.spec(:ex_cldr) ->
        Keyword.get(spec, :vsn) |> :erlang.list_to_binary
      Code.ensure_loaded?(Cldr.Mixfile) ->
        Keyword.get(Cldr.Mixfile.project(), :version)
      true ->
        :error
    end
  end

  # Get the git branch name based upon the app version
  defp branch_from_version do
    version = app_version()

    if String.contains?(version, "-dev") do
      "master"
    else
      "v#{version}"
    end
  end

  @doc """
  Returns a `boolean` indicating if the requested locale is installed.

  No checking of the validity of the `locale` itself is performed.  The
  check is based upon whether there is a locale file installed in the
  client application or in `Cldr` itself.
  """
  def locale_installed?(locale) do
    case Cldr.Config.locale_path(locale) do
      {:ok, _path} -> true
      _            -> false
    end
  end

  @doc """
  Returns the full pathname of the locale's json file.

  * `locale` is any locale returned by `Cldr.known_locales{}`

  No checking of locale validity is performed.
  """
  def client_locale_file(locale) do
    Path.join(client_locales_dir(), "#{locale}.json")
  end

  # Create the client app locales directory and any directories
  # that don't exist above it.
  defp ensure_client_dirs_exist!(dir) do
    paths = String.split(dir, "/")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(String.replace_prefix(&1, "", "/")))
    do_ensure_client_dirs(paths)
  end

  defp do_ensure_client_dirs([h | []]) do
    create_dir(h)
  end

  defp do_ensure_client_dirs([h | t]) do
    create_dir(h)
    do_ensure_client_dirs([h <> hd(t) | tl(t)])
  end

  defp create_dir(dir) do
    case File.mkdir(dir) do
      :ok ->
        :ok
      {:error, :eexist} ->
        :ok
      {:error, :eisdir} ->
        :ok
      {:error, code} ->
        raise RuntimeError,
          message: "Couldn't create #{dir}: #{inspect code}"
    end
  end
end
