defmodule Cldr.UnknownLocaleError do
  @moduledoc """
  Exception raised when an attempt is made to use a locale not configured
  in `Cldr`.  `Cldr.known_locales/0` returns the locale names known to `Cldr`.
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.UnknownNumberSystemError do
  @moduledoc """
  Exception raised when an attempt is made to use a number system that is not known
  in `Cldr`.  `Cldr.Number.number_system_names/0` returns the number system names known to `Cldr`.
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.UnknownFormatError do
  @moduledoc """
  Exception raised when an attempt is made to use a locale that is not configured
  in `Cldr`.  `Cldr.known_locales/0` returns the locale names known to `Cldr`.
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.UnknownUnitError do
  @moduledoc """
  Exception raised when an attempt is made to use a unit that is not known
  in `Cldr`.
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.FormatError do
  @moduledoc """
  Exception raised when there is an error in the formatting of a number/list/...
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.FormatCompileError do
  @moduledoc """
  Exception raised when there is an error in the compiling of a number format
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Cldr.UnknownCurrencyError do
  @moduledoc """
  Exception raised when there is an invalid currncy code
  """
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end
