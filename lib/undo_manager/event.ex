defmodule Yex.UndoManager.Event do
  @moduledoc """
  Represents an UndoManager event.
  """
  defstruct [:meta, :origin, :kind]
end
