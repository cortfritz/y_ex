defmodule Yex.XmlText do
  @moduledoc """
  Extends Y.Text to represent a Y.Xml node.


  """

  defstruct [
    :doc,
    :reference
  ]

  @type delta :: Yex.Text.delta()

  @spec insert(t, integer(), Yex.input_type()) :: :ok | :error
  def insert(%__MODULE__{} = xml_text, index, content) do
    Yex.Nif.xml_text_insert(xml_text, index, content)
  end

  @spec insert(t, integer(), Yex.input_type(), map()) :: :ok | :error
  def insert(%__MODULE__{} = xml_text, index, content, attr) do
    Yex.Nif.xml_text_insert_with_attributes(xml_text, index, content, attr)
  end

  @spec delete(t, integer(), integer()) :: :ok | :error
  def delete(%__MODULE__{} = xml_text, index, length) do
    index = if index < 0, do: __MODULE__.length(xml_text) + index, else: index
    Yex.Nif.xml_text_delete(xml_text, index, length) |> Yex.Nif.Util.unwrap_ok_tuple()
  end

  @spec format(t, integer(), integer(), map()) :: :ok | :error
  def format(%__MODULE__{} = xml_text, index, length, attr) do
    Yex.Nif.xml_text_format(xml_text, index, length, attr)
  end

  @spec apply_delta(t, delta) :: :ok | :error
  def apply_delta(%__MODULE__{} = xml_text, delta) do
    Yex.Nif.xml_text_apply_delta(xml_text, delta)
  end

  def to_delta(%__MODULE__{} = text) do
    Yex.Nif.xml_text_to_delta(text)
  end

  @spec to_string(t) :: binary()
  def to_string(%__MODULE__{} = xml_text) do
    Yex.Nif.xml_text_to_string(xml_text)
  end

  @spec length(t) :: integer()
  def length(%__MODULE__{} = xml_text) do
    Yex.Nif.xml_text_length(xml_text)
  end

  @type t :: %__MODULE__{
          doc: reference(),
          reference: reference()
        }
  def next_sibling(%__MODULE__{} = xml_text) do
    Yex.Nif.xml_text_next_sibling(xml_text)
  end

  def prev_sibling(%__MODULE__{} = xml_text) do
    Yex.Nif.xml_text_prev_sibling(xml_text)
  end
end

defmodule Yex.XmlTextPrelim do
  @moduledoc """
  A preliminary xml text. It can be used to early initialize the contents of a XmlText.

  ## Examples
      iex> doc = Yex.Doc.new()
      iex> xml = Yex.Doc.get_xml_fragment(doc, "xml")
      iex> Yex.XmlFragment.insert(xml, 0,  Yex.XmlTextPrelim.from("Hello World"))
      iex> {:ok, %Yex.XmlText{} = text} = Yex.XmlFragment.get(xml, 0)
      iex> Yex.XmlText.to_delta(text)
      [%{insert: "Hello World"}]

  """
  defstruct [:text]
  #  defstruct [
  #    :delta,
  #    :attributes
  #  ]

  @type t :: %__MODULE__{
          text: binary()
          #    delta: Yex.Text.delta()
        }

  @spec from(binary()) :: t
  def from(text) when is_binary(text) do
    %__MODULE__{text: text}
  end

  #  @spec from(Yex.Text.delta()) :: t
  #  def from(delta) do
  #    %__MODULE__{delta: delta}
  #  end
end