defmodule Yex.UndoManager.Options do
  @moduledoc """
  Options for creating an UndoManager.

  * `:capture_timeout` - Time in milliseconds to wait before creating a new capture group
  """
  defstruct capture_timeout: 500  # Default from Yrs

  @type t :: %__MODULE__{
    capture_timeout: non_neg_integer()
  }
end
