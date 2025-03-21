defmodule Kafee.EncoderDecoder do
  @moduledoc """
  A behaviour for implementing encoders and decoders in Kafee. These are designed
  to allow easier usage automatically encoding and decoding native data structures
  to binary. They have the added bonus of decoding binary data to native data
  structures while testing to avoid issues like JSON key sorting in OTP 26+.
  """

  @doc """
  Returns the content type of the encoder decoder. This will be set as the
  `content-type` header in the Kafka message.
  """
  @callback content_type() :: String.t()

  @doc """
  Encodes a native data type (like a struct) into binary to be set as a
  Kafka message value.
  """
  @callback encode!(any, Keyword.t()) :: binary

  @doc """
  Decodes binary data into a native data type. Will raise an error if there
  is an issue decoding the data.
  """
  @callback decode!(binary, Keyword.t()) :: any

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end
end
