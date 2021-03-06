# credo:disable-for-this-file
if Code.ensure_loaded?(Experimental.Flow) do
  defmodule Cldr.Consolidate do
    @moduledoc """
    Consolidates all locale-specific information from the CLDR repository into
    one locale-specific file.
    """

    alias Cldr.Normalize

    defdelegate download_data_dir(), to: Cldr.Config
    defdelegate consolidated_output_dir(), to: Cldr.Config, as: :source_data_dir

    @doc """
    Returns the directory where the locale-specific json files are stored.
    """
    def consolidated_locales_dir do
      Path.join(consolidated_output_dir(), "/locales")
    end

    @doc """
    Consolidates all available CLDR locale-specific json files into a set of
    locale-specific json files, one per locale.

    Also formats non-locale-specific CLDR data that is core to `Cldr`
    operation.
    """
    @max_demand 50
    @spec consolidate_locales :: :ok
    def consolidate_locales do
      alias Experimental.Flow

      ensure_output_dir_exists!(consolidated_output_dir())
      ensure_output_dir_exists!(consolidated_locales_dir())

      save_cldr_version()
      save_plurals()
      save_number_systems()
      save_currencies()
      save_locales()

      all_locales()
      |> Flow.from_enumerable(max_demand: @max_demand)
      |> Flow.map(&consolidate_locale/1)
      |> Enum.to_list
      :ok
    end

    @doc """
    Consolidates known locales as defined by `Cldr.known_locales/0`.
    """
    @spec consolidate_known_locales :: :ok
    def consolidate_known_locales do
      alias Experimental.Flow

      Cldr.known_locales()
      |> Flow.from_enumerable(max_demand: @max_demand)
      |> Flow.map(&consolidate_locale/1)
      |> Enum.to_list
      :ok
    end

    @doc """
    Consolidates one locale.

    * `locale` is any locale defined by `Cldr.all_locales/0`
    """
    def consolidate_locale(locale) do
      IO.puts "Consolidating locale #{locale}"
      cldr_locale_specific_dirs()
      |> consolidate_locale_content(locale)
      |> level_up_locale(locale)
      |> Cldr.Map.underscore_keys
      |> normalize_content(locale)
      |> Map.take(Cldr.Config.required_modules())
      |> Cldr.Map.atomize_keys
      |> save_locale(locale)
    end

    def consolidate_locale_content(locale_dirs, locale) do
      locale_dirs
      |> Enum.map(&locale_specific_content(locale, &1))
      |> merge_maps
    end

    defp normalize_content(content, locale) do
      Normalize.Number.normalize(content, locale)
      |> Normalize.Currency.normalize(locale)
      |> Normalize.List.normalize(locale)
      |> Normalize.NumberSystem.normalize(locale)
      |> Normalize.Rbnf.normalize(locale)
      |> Normalize.Units.normalize(locale)
      |> Normalize.DateFields.normalize(locale)
    end

    # Remove the top two levels of the map since they add nothing
    # but more levels :-)
    defp level_up_locale(content, locale) do
      get_in(content, ["main", locale])
    end

    defp save_locale(content, locale) do
      output_path = Path.join(consolidated_locales_dir(), "#{locale}.json")
      File.write!(output_path, Poison.encode!(content))
    end

    defp merge_maps([file_1]) do
      file_1
    end

    defp merge_maps([file_1, file_2]) do
      Cldr.Map.deep_merge(file_1, file_2)
    end

    defp merge_maps([file | rest]) do
      Cldr.Map.deep_merge(file, merge_maps(rest))
    end

    defp locale_specific_content(locale, directory) do
      dir = Path.join(directory, ["main/", locale])

      with {:ok, files} <- File.ls(dir) do
        Enum.map(files, &Path.join(dir, &1))
        |> Enum.map(&File.read!(&1))
        |> Enum.map(&Poison.decode!(&1))
        |> merge_maps
      else
        {:error, _} -> %{}
      end
    end

    def cldr_locale_specific_dirs do
      cldr_directories()
      |> Enum.filter(&locale_specific_dir?/1)
    end

    defp locale_specific_dir?(filename) do
      String.ends_with?(filename, "-full")
    end

    def cldr_directories do
      download_data_dir()
      |> File.ls!
      |> Enum.filter(&cldr_dir?/1)
      |> Enum.map(&Path.join(download_data_dir(), &1))
    end

    defp cldr_dir?("common") do
      true
    end

    defp cldr_dir?(filename) do
      String.starts_with?(filename, "cldr-")
    end

    defp ensure_output_dir_exists!(dir) do
      case File.mkdir(dir) do
        :ok ->
          :ok
        {:error, :eexist} ->
          :ok
        {:error, code} ->
          raise RuntimeError,
            message: "Couldn't create #{dir}: #{inspect code}"
      end
    end

    # As of CLDR 31 there is an available locale es-BZ that has no content and
    # therefore should not be included
    @invalid_locales []

    def all_locales() do
      download_data_dir()
      |> Path.join(["cldr-core", "/availableLocales.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["availableLocales", "full"])
      |> Kernel.--(@invalid_locales)
    end

    defp cldr_version() do
      download_data_dir()
      |> Path.join(["cldr-core", "/package.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["version"])
    end

    defp save_cldr_version do
      path = Path.join(consolidated_output_dir(), "version.json")
      save_file(cldr_version(), path)

      assert_package_file_configured!(path)
    end

    defp save_locales do
      path = Path.join(consolidated_output_dir(), "available_locales.json")
      save_file(all_locales(), path)

      assert_package_file_configured!(path)
    end

    defp save_plurals do
      cardinal = Path.join(download_data_dir(), ["cldr-core", "/supplemental", "/plurals.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["supplemental", "plurals-type-cardinal"])

      ordinal = Path.join(download_data_dir(), ["cldr-core", "/supplemental", "/ordinals.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["supplemental", "plurals-type-ordinal"])

      content = %{cardinal: cardinal, ordinal: ordinal}
      path = Path.join(consolidated_output_dir(), "plural_rules.json")
      save_file(content, path)

      assert_package_file_configured!(path)
    end

    defp save_number_systems do
      path = Path.join(consolidated_output_dir(), "number_systems.json")
      Path.join(download_data_dir(), ["cldr-core", "/supplemental", "/numberingSystems.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["supplemental", "numberingSystems"])
      |> remove_leading_underscores
      |> save_file(path)

      assert_package_file_configured!(path)
    end

    def save_currencies do
      path = Path.join(consolidated_output_dir(), "currencies.json")
      Path.join(download_data_dir(), ["cldr-numbers-full", "/main", "/en", "/currencies.json"])
      |> File.read!
      |> Poison.decode!
      |> get_in(["main", "en", "numbers", "currencies"])
      |> Map.keys
      |> save_file(path)

      assert_package_file_configured!(path)
    end

    def assert_package_file_configured!(path) do
      [_, path] = String.split(path, "/priv/")
      path = "priv/" <> path

      if path in Mix.Project.config[:package][:files] do
        :ok
      else
        raise "Path #{path} is not in the package definition"
      end
    end

    defp remove_leading_underscores(%{} = systems) do
      Enum.map(systems, fn {k, v} ->
        {String.replace_prefix(k, "_", ""), remove_leading_underscores(v)} end)
      |> Enum.into(%{})
    end

    defp remove_leading_underscores(v) do
      v
    end

    defp save_file(content, path) do
      File.write!(path, Poison.encode!(content))
    end
  end
end