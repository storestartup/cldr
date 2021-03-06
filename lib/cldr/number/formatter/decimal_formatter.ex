defmodule Cldr.Number.Formatter.Decimal do
  @moduledoc """
  Formats a number according to a locale-specific predefined format or a user-defined format.

  As a performance optimization, all decimal formats known at compile time are
  compiled into function that roughly halves the time to format a number
  compared to a non-precompiled format.

  The available format styles for a locale can be returned by:

      iex> Cldr.Number.Format.decimal_format_styles_for "en"
      [:accounting, :currency, :currency_long, :percent, :scientific, :standard]

  This allows a number to be formatted in a locale-specific way but using
  a standard method of describing the purpose of the format.

  ## Examples

      iex> Number.to_string 1234, format: :accounting, currency: "JPY"
      "¥1,234"

      iex> Number.to_string -1234, format: :accounting, currency: "JPY"
      "(¥1,234)"

  User defined formats can also be used.  See `Cldr.Number.Format` for
  more information on defining number formats.

  Examples:

      iex> Number.to_string 12345, format: "#,##0.00"
      "12,345.00"

      iex> Number.to_string 12345, format: "0000.00"
      "2345.00"

      iex> Number.to_string 12345, format: "000000"
      "012345"

      # Rounds to the nearest 6.00
      iex> Number.to_string 12345, format: "#,##6.00"
      "12,348.00"
  """

  import Cldr.Macros
  import Cldr.Number.Transliterate, only: [transliterate: 3]
  import Cldr.Number.Symbol,        only: [number_symbols_for: 2]
  import Cldr.Math,                 only: [power_of_10: 1]

  alias Cldr.{Currency, Number, Math, Digits}
  alias Cldr.Number.Format
  alias Cldr.Number.Format.Compiler

  @empty_string ""

  # Precompile the known formats
  for format <- Cldr.Number.Format.decimal_format_list() do
    case Compiler.decode(format) do
    {:ok, meta} ->
      def to_string(number, unquote(format), options) do
        do_to_string(number, unquote(Macro.escape(meta)), options)
      end
    {:error, message} ->
      raise Cldr.FormatCompileError, "#{message} compiling #{inspect format}"
    end
  end

  # For formats not precompiled we need to compile first
  # and then process.
  def to_string(number, format, options) do
    case Compiler.decode(format) do
    {:ok, meta} ->
      do_to_string(number, meta, options)
    {:error, message} ->
      {:error, {Cldr.FormatCompileError, message}}
    end
  end

  # Now we have the number to be formatted, the meta data that
  # defines the formatting and the options to be applied
  # (which is related to localisation of the final format)

  # This first version is an optimization for integers using the
  # standard format since its the most common.
  @standard_format %{format:
    [positive: [format: "#,##0.###"], negative: [minus: '-', format: :same_as_positive]]}

  # For negative numbers in the standard format
  defp do_to_string(number, @standard_format = meta, options)
  when is_number(number) and number < 0 do
    system   = options[:number_system]
    locale   = options[:locale]
    symbols  = number_symbols_for(locale, system)

    if (number_string = do_to_string(abs(number), meta, options)) == "0" do
      number_string
    else
      system   = options[:number_system]
      locale   = options[:locale]
      symbols  = number_symbols_for(locale, system)
      symbols.minus_sign <> do_to_string(abs(number), meta, options)
    end
  end

  defp do_to_string(number, @standard_format = meta, options) when is_integer(number) do
    number
    |> output_to_tuple(meta)
    |> apply_grouping(meta[:grouping], options[:locale])
    |> reassemble_number_string(meta)
    |> transliterate(options[:locale], options[:number_system])
  end

  # Optimization for a float in the standard format
  defp do_to_string(number, @standard_format = meta, options) when is_float(number) do
    meta = meta
    |> adjust_for_fractional_digits(options[:fractional_digits])

    {number, 0}
    |> round_fractional_digits(meta, options[:rounding_mode])
    |> output_to_tuple(meta)
    |> adjust_trailing_zeros(:fraction, meta)
    |> apply_grouping(meta[:grouping], options[:locale])
    |> reassemble_number_string(meta)
    |> transliterate(options[:locale], options[:number_system])
  end

  defp do_to_string(number, %{integer_digits: _integer_digits} = meta, options) do
    meta = meta
    |> adjust_fraction_for_currency(options[:currency], options[:cash])
    |> adjust_fraction_for_significant_digits(number)
    |> adjust_for_fractional_digits(options[:fractional_digits])

    number
    |> absolute_value
    |> multiply_by_factor(meta)
    |> round_to_significant_digits(meta)
    |> round_to_nearest(meta, options[:rounding_mode])
    |> set_exponent(meta)
    |> round_fractional_digits(meta, options[:rounding_mode])
    |> output_to_tuple(meta)
    |> adjust_leading_zeros(:integer, meta)
    |> adjust_trailing_zeros(:fraction, meta)
    |> set_max_integer_digits(meta)
    |> apply_grouping(meta[:grouping], options[:locale])
    |> reassemble_number_string(meta)
    |> transliterate(options[:locale], options[:number_system])
    |> assemble_format(number, meta, options)
  end

  # For when the format itself actually has only literal components
  # and no number format.
  defp do_to_string(number, meta, options) do
    assemble_format("", number, meta, options)
  end

  # We work with the absolute value because the formatting of the sign
  # is done by selecting the "negative format" rather than the "positive format"
  def absolute_value(%Decimal{} = number) do
    Decimal.abs(number)
  end

  def absolute_value(number) do
    abs(number)
  end

  # If the format includes a % (percent) or permille then we
  # adjust the number by a factor.  All other formats the factor
  # is 1 and hence we avoid the multiplication.
  defp multiply_by_factor(number, 1 = _factor) do
    number
  end

  defp multiply_by_factor(%Decimal{} = number, %{multiplier: factor}) when is_integer(factor) do
    Decimal.mult(number, Decimal.new(factor))
  end

  defp multiply_by_factor(number, %{multiplier: factor})
  when is_number(number) and is_number(factor) do
    number * factor
  end

  # When formatting a currency we need to adjust the number of fractional
  # digits to match the currency definition.  We also need to adjust the
  # rounding increment to match the currency definition. Note that here
  # we are just adjusting the meta data, not the number itself
  defp adjust_fraction_for_currency(meta, nil, _cash) do
    meta
  end

  defp adjust_fraction_for_currency(meta, currency, cash) when is_false(cash) do
    currency = Currency.for_code(currency)
    do_adjust_fraction(meta, currency.digits, currency.rounding)
  end

  defp adjust_fraction_for_currency(meta, currency, _cash) do
    currency = Currency.for_code(currency)
    do_adjust_fraction(meta, currency.cash_digits, currency.cash_rounding)
  end

  defp do_adjust_fraction(meta, digits, rounding) do
    rounding = power_of_10(-digits) * rounding
    %{meta | fractional_digits: %{max: digits, min: digits},
             rounding: rounding}
  end

  # If we round to sigificant digits then the format won't (usually)
  # have any fractional part specified and if we don't do something
  # then we're truncating the number - not really what is intended
  # for significant digits display.

  # For when there is no number format
  defp adjust_fraction_for_significant_digits(
      %{significant_digits: nil} = meta, _number) do
    meta
  end

  # For no significant digits
  defp adjust_fraction_for_significant_digits(
      %{significant_digits: %{max: 0, min: 0}} = meta, _number) do
    meta
  end

  # No fractional digits for an integer
  defp adjust_fraction_for_significant_digits(
      %{significant_digits: %{max: _max, min: _min}} = meta, number)
  when is_integer(number) do
    meta
  end

  # Decimal version of an integer => exponent > 0
  defp adjust_fraction_for_significant_digits(
      %{significant_digits: %{max: _max, min: _min}} = meta,
  %Decimal{exp: exp}) when exp >= 0 do
    meta
  end

  # For all float or Decimal fraction
  defp adjust_fraction_for_significant_digits(
      %{significant_digits: %{max: _max, min: _min}} = meta, _number) do
    %{meta | fractional_digits: %{max: 10, min: 1}}
  end

  # To allow overriding fractional digits
  defp adjust_for_fractional_digits(meta, nil) do
    meta
  end

  defp adjust_for_fractional_digits(meta, digits) do
    %{meta | fractional_digits: %{max: digits, min: digits}}
  end

  # Round to significant digits.  This is different to rounding
  # to decimal places and is a more expensive mathematical
  # calculation.  Although the specification allows for minimum
  # and maximum, I haven't found an example of where minimum is a
  # useful rounding value since maximum already removes trailing
  # insignificant zeros.
  #
  # Also note that this implementation allows for both significant
  # digit rounding as well as decimal precision rounding.  Its likely
  # not a good idea to combine the two in a format mask and results
  # are unspecified if you do.
  defp round_to_significant_digits(number, %{significant_digits: %{min: 0, max: 0}}) do
    number
  end

  defp round_to_significant_digits(number, %{significant_digits: %{min: _min, max: max}}) do
    Math.round_significant(number, max)
  end

  # Round to nearest rounds a number to the nearest increment specified.  For example
  # if `rounding: 5` then we round to the nearest multiple of 5.  The appropriate rounding
  # mode is used.
  defp round_to_nearest(number, %{rounding: rounding}, _rounding_mode)
  when rounding == 0 do
    number
  end

  defp round_to_nearest(%Decimal{} = number, %{rounding: rounding}, rounding_mode) do
    rounding = Decimal.new(rounding)

    number
    |> Decimal.div(rounding)
    |> Math.round(0, rounding_mode)
    |> Decimal.mult(rounding)
  end

  defp round_to_nearest(number, %{rounding: rounding}, rounding_mode)
  when is_float(number) do
    number
    |> Kernel./(rounding)
    |> Math.round(0, rounding_mode)
    |> Kernel.*(rounding)
  end

  defp round_to_nearest(number, %{rounding: rounding}, rounding_mode)
  when is_integer(number) do
    number
    |> Kernel./(rounding)
    |> Math.round(0, rounding_mode)
    |> Kernel.*(rounding)
    |> trunc
  end

  # For a scientific format we need to adjust to a
  # mantissa * 10^exponent format.
  defp set_exponent(number, %{exponent_digits: exponent_digits})
  when exponent_digits == 0 do
    {number, 0}
  end

  defp set_exponent(number, meta) do
    {mantissa, exponent} = Math.mantissa_exponent(number)

    mantissa = if meta.scientific_rounding > 0 do
      Math.round_significant(mantissa, meta.scientific_rounding)
    else
      mantissa
    end

    {mantissa, exponent}
  end

  # Round to get the right number of fractional digits.  This is
  # applied after setting the exponent since we may have either
  # the original number or its mantissa form.
  defp round_fractional_digits({number, exponent}, _options, _rounding_mode)
  when is_integer(number) do
    {number, exponent}
  end

  # Don't round if we're in exponential mode.  This is probably incorrect since
  # we're not following the 'significant digits' processing rule for
  # exponent numbers.
  defp round_fractional_digits({number, exponent}, %{exponent_digits: exponent_digits},
        _rounding_mode) when exponent_digits > 0 do
    {number, exponent}
  end

  defp round_fractional_digits({number, exponent},
      %{fractional_digits: %{max: max, min: _min}}, rounding_mode) do
    number = Math.round(number, max, rounding_mode)
    {number, exponent}
  end

  # Output the number to a tuple - all the other transformations
  # are done on the tuple version split into its constituent
  # parts
  defp output_to_tuple(number, _meta) when is_integer(number) do
    integer = :erlang.integer_to_list(number)
    {1, integer, [], 1, [?0]}
  end

  defp output_to_tuple({mantissa, exponent}, _meta) do
    {integer, fraction, sign} = Digits.to_tuple(mantissa)
    exponent_sign = if exponent >= 0, do: 1, else: -1
    integer = Enum.map(integer, &Kernel.+(&1, ?0))
    fraction = Enum.map(fraction, &Kernel.+(&1, ?0))
    exponent = if exponent == 0, do: [?0], else: Integer.to_charlist(abs(exponent))
    {sign, integer, fraction, exponent_sign, exponent}
  end

  # Remove all the leading zeros from an integer and add back what
  # is required for the format
  defp adjust_leading_zeros({sign, integer, fraction, exponent_sign, exponent},
      :integer, %{integer_digits: integer_digits}) do
    integer = if (count = integer_digits[:min] - length(integer)) > 0 do
      :lists.duplicate(count, ?0) ++ integer
    else
      integer
    end
    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp adjust_leading_zeros(number, _integer, %{integer_digits: _integer_digits}) do
    number
  end

  defp adjust_trailing_zeros({sign, integer, fraction, exponent_sign, exponent},
      :fraction, %{fractional_digits: fraction_digits}) do
    fraction = do_trailing_zeros(fraction,fraction_digits[:min] - length(fraction))
    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp adjust_trailing_zeros(number, _fraction, %{fractional_digits: _fraction_digits}) do
    number
  end

  defp do_trailing_zeros(fraction, count) when count <= 0 do
    fraction
  end

  defp do_trailing_zeros(fraction, count) do
    fraction ++ :lists.duplicate(count, ?0)
  end

  # Take the rightmost maximum digits only - this is a truncation from the
  # right.
  defp set_max_integer_digits(number, %{integer_digits: %{max: max}}) when max == 0 do
    number
  end

  defp set_max_integer_digits({sign, integer, fraction, exponent_sign, exponent},
      %{integer_digits: %{max: max}}) do
    integer = do_max_integer_digits(integer, length(integer) - max)
    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp do_max_integer_digits(integer, over) when over <= 0 do
    integer
  end

  defp do_max_integer_digits(integer, over) do
    {_rest, integer} = Enum.split(integer, over)
    integer
  end

  # Insert the grouping placeholder in the right place in the number.
  # There may be one or two different groupings for the integer part
  # and one grouping for the fraction part.
  defp apply_grouping({sign, integer, [] = fraction, exponent_sign, exponent}, groups, locale) do
    integer  = do_grouping(integer, groups[:integer], length(integer),
                 minimum_group_size(groups[:integer], locale), :reverse)

    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp apply_grouping({sign, integer, fraction, exponent_sign, exponent}, groups, locale) do
    integer  = do_grouping(integer, groups[:integer], length(integer),
                 minimum_group_size(groups[:integer], locale), :reverse)

    fraction = do_grouping(fraction, groups[:fraction], length(fraction),
                 minimum_group_size(groups[:fraction], locale), :forward)

    {sign, integer, fraction, exponent_sign, exponent}
  end

  defp minimum_group_size(%{first: group_size}, locale) do
    Format.minimum_grouping_digits_for(locale) + group_size
  end

  # The actual grouping function.  Note there are two directions,
  # `:forward` and `:reverse`.  Thats because we group from the decimal
  # placeholder outwards and there may be a final group that is less than
  # the grouping size.  For the fraction part the dangling part is at the
  # end (:forward direction) whereas for the integer part the dangling
  # group is at the beginning (:reverse direction)

  # No grouping if the length (number of digits) is less than the
  # minimum grouping size.
  defp do_grouping(number, _, length, min_grouping, _) when length < min_grouping do
    number
  end

  # The case when there is only one grouping. Always true for fraction part.
  @group_separator Compiler.placeholder(:group)
  defp do_grouping(number, %{first: 0, rest: 0}, _, _, _) do
    number
  end

  defp do_grouping(number, %{first: first, rest: rest}, length, _, :forward) when first == rest do
    split_point = div(length, first) * first
    {rest, last_group} = Enum.split(number, split_point)

    add_separator(rest, first, @group_separator)
    |> add_last_group(last_group, @group_separator)
  end

  defp do_grouping(number, %{first: first, rest: rest}, length, _, _direction)
  when first == rest and length <= first do
    number
  end

  defp do_grouping(number, %{first: first, rest: rest}, length, _, :reverse) when first == rest do
    split_point = length - (div(length, first) * first)
    {first_group, rest} = Enum.split(number, split_point)

    add_separator(rest, first, @group_separator)
    |> add_first_group(first_group, @group_separator)
  end

  # The case when there are two different groupings. This applies only to
  # The integer part, it can never be true for the fraction part.
  defp do_grouping(number, %{first: first, rest: rest}, length, _min_grouping, :reverse) do
    {others, first_group} = Enum.split(number, length - first)
    do_grouping(others, %{first: rest, rest: rest}, length(others), 1, :reverse)
    |> add_last_group(first_group, @group_separator)
  end

  defp add_separator([], _every, _separator) do
    []
  end

  defp add_separator(group, every, separator) do
    {_, [_ | rest]} = Enum.reduce group, {1, []}, fn elem, {counter, list} ->
      list = [elem | list]
      list = if rem(counter, every) == 0 do
        [separator | list]
      else
        list
      end
      {counter + 1, list}
    end

    Enum.reverse(rest)
  end

  defp add_first_group(groups, [], _separator) do
    groups
  end

  defp add_first_group(groups, first, separator) do
    [first, separator, groups]
  end

  defp add_last_group(groups, [], _separator) do
    groups
  end

  defp add_last_group(groups, last, separator) do
    [groups, separator, last]
  end

  @decimal_separator  Compiler.placeholder(:decimal)
  @exponent_separator Compiler.placeholder(:exponent)
  @exponent_sign      Compiler.placeholder(:exponent_sign)
  @minus_placeholder  Compiler.placeholder(:minus)
  defp reassemble_number_string({_sign, integer, fraction, exponent_sign, exponent}, meta) do
    integer  = if integer  == [],  do: ['0'], else: integer
    fraction = if fraction == [],  do: fraction, else: [@decimal_separator, fraction]

    exponent_sign = cond do
       exponent_sign < 0  -> @minus_placeholder
       meta.exponent_sign -> @exponent_sign
       true               -> ''
     end

    exponent = if meta.exponent_digits > 0 do
      [@exponent_separator, exponent_sign, exponent]
    else
      []
    end

    :erlang.iolist_to_binary([integer, fraction, exponent])
  end

  # Now we can assemble the final format.  Based upon
  # whether the number is positive or negative (as indicated
  # by options[:sign]) we assemble the parts and transliterate
  # the currency sign, percent and permille characters.
  defp assemble_format(number_string, number, meta, options) do
    format = meta.format[options[:pattern]]

    number_string
    |> do_assemble_format(number, meta, format, options)
    |> :erlang.iolist_to_binary
  end

  defp do_assemble_format(number_string, number, meta, format, options) do
    system   = options[:number_system]
    locale   = options[:locale]
    currency = options[:currency]
    symbols  = number_symbols_for(locale, system)

    Enum.map format, fn (token) ->
      case token do
        {:format, _format}   -> number_string
        {:pad, _}            -> padding_string(meta, number_string)
        {:plus, _}           -> symbols.plus_sign
        {:minus, _}          -> if number_string == "0", do: "", else: symbols.minus_sign
        {:currency, type}    -> currency_symbol(currency, number, type, locale)
        {:percent, _}        -> symbols.percent_sign
        {:permille, _}       -> symbols.permille
        {:literal, literal}  -> literal
        {:quote, _char}      -> "'"
        {:quoted_char, char} -> char
      end
    end
  end

  # Calculate the padding by subtracting the length of the number
  # string from the padding length.
  defp padding_string(%{padding_length: 0}, _number_string) do
    @empty_string
  end

  # We can't make the assumption that the padding character is
  # an ascii character - it could be any grapheme so we can't use
  # binary pattern matching.
  defp padding_string(meta, number_string) do
    pad_length = meta[:padding_length] - String.length(number_string)
    if pad_length > 0 do
      String.duplicate(meta[:padding_char], pad_length)
    else
      @empty_string
    end
  end

  # Extract the appropriate currency symbol based upon how many currency
  # placeholders are in the format as follows:
  #   ¤      Standard currency symbol
  #   ¤¤     ISO currency symbol (constant)
  #   ¤¤¤    Appropriate currency display name for the currency, based on the
  #          plural rules in effect for the locale
  #   ¤¤¤¤   Narrow currency symbol.
  defp currency_symbol(%Currency{} = currency, _number, 1, _locale) do
    currency.symbol
  end

  defp currency_symbol(%Currency{} = currency, _number, 2, _locale) do
    currency.code
  end

  defp currency_symbol(%Currency{} = currency, number, 3, locale) do
    Number.Cardinal.pluralize(number, locale, currency.count)
  end

  defp currency_symbol(%Currency{} = currency, _number, 4, _locale) do
    currency.narrow_symbol || currency.symbol
  end

  defp currency_symbol(currency, number, size, locale) do
    currency = Currency.for_code(currency, locale)
    currency_symbol(currency, number, size, locale)
  end
end