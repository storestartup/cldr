defmodule Cldr.Locale do
  @moduledoc """
  Parse and process locale json as defined by [Unicode](http://unicode.org/reports/tr35/#Unicode_Language_and_Locale_Identifiers)
  """
  defstruct [:name, :currencies, :date_fields, :list_formats, :minimum_grouping_digits,
   :number_formats, :number_symbols, :number_systems, :rbnf, :units]

  @type name :: binary

  def normalize_locale_name(locale_name) do
    String.replace(locale_name, "_", "-")
  end

  def locale_error(locale_name) do
    {Cldr.UnknownLocaleError, "The locale #{inspect locale_name} is not known"}
  end
end