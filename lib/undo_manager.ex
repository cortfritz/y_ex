defmodule Yex.UndoManager do
  require Logger
  alias Yex.UndoManager.Options

  @type t :: %__MODULE__{reference: reference()}
  @type metadata :: %{required(String.t()) => term()} | nil

  # Keep just the reference field since we no longer need pid
  defstruct [:reference]

  def new(doc, %Yex.Text{} = scope) do
    Logger.debug("Creating new UndoManager for Text scope")
    new_with_options(doc, scope, %Options{})
  end

  def new(doc, %Yex.Array{} = scope), do: new_with_options(doc, scope, %Options{})
  def new(doc, %Yex.Map{} = scope), do: new_with_options(doc, scope, %Options{})

  def new_with_options(doc, %Yex.Text{} = scope, %Options{} = options) do
    Logger.debug("Creating new UndoManager for Text scope")
    Logger.debug("Creating UndoManager with options: #{inspect(options)}")

    case Yex.Nif.undo_manager_new_with_options(doc, {:text, scope}, options) do
      {:ok, ref} ->
        Logger.debug("Successfully created UndoManager with ref: #{inspect(ref)}")
        %__MODULE__{reference: ref}
      {:error, reason} ->
        Logger.error("Failed to create UndoManager: #{inspect(reason)}")
        raise "Failed to create UndoManager: #{inspect(reason)}"
      other ->
        Logger.error("Unexpected return from NIF: #{inspect(other)}")
        raise "Unexpected return from NIF: #{inspect(other)}"
    end
  end

  def new_with_options(doc, %Yex.Array{} = scope, %Options{} = options) do
    case Yex.Nif.undo_manager_new_with_options(doc, {:array, scope}, options) do
      {:ok, manager} -> %__MODULE__{reference: manager.reference}
      error -> error
    end
  end

  def new_with_options(doc, %Yex.Map{} = scope, %Options{} = options) do
    case Yex.Nif.undo_manager_new_with_options(doc, {:map, scope}, options) do
      {:ok, manager} -> %__MODULE__{reference: manager.reference}
      error -> error
    end
  end

  # Direct NIF calls without GenServer
  def include_origin(%__MODULE__{reference: ref}, origin) do
    Logger.debug("Including origin: #{inspect(origin)}")
    Yex.Nif.undo_manager_include_origin(ref, origin)
  end

  def exclude_origin(%__MODULE__{reference: ref}, origin), do: Yex.Nif.undo_manager_exclude_origin(ref, origin)
  def undo(%__MODULE__{reference: ref}) do
    Logger.debug("Performing undo operation with ref: #{inspect(ref)}")
    case Yex.Nif.undo_manager_undo(ref) do
      {:ok, _} -> :ok
      error ->
        Logger.error("Undo operation failed with error: #{inspect(error)}")
        raise "Undo operation failed: #{inspect(error)}"
    end
  end

  def redo(%__MODULE__{reference: ref}), do: Yex.Nif.undo_manager_redo(ref)
  def expand_scope(%__MODULE__{reference: ref}, scope), do: Yex.Nif.undo_manager_expand_scope(ref, scope)
  def stop_capturing(%__MODULE__{reference: ref}), do: Yex.Nif.undo_manager_stop_capturing(ref)
  def clear(%__MODULE__{reference: ref}), do: Yex.Nif.undo_manager_clear(ref)

  @doc """
  Adds an observer for stack item added events.
  """
  @spec add_added_observer(%__MODULE__{}, pid()) :: :ok | {:error, term()}
  def add_added_observer(%__MODULE__{reference: ref}, callback) when is_function(callback, 1) do
    # Wrap the callback to return new metadata instead of mutating
    observer = fn event ->
      new_meta = callback.(event)
      {:ok, new_meta}
    end
    Yex.Nif.undo_manager_add_added_observer(ref, observer)
  end

  @doc """
  Adds an observer for stack item updated events.
  """
  @spec add_updated_observer(%__MODULE__{}, pid()) :: :ok | {:error, term()}
  def add_updated_observer(%__MODULE__{reference: ref}, observer_pid) do
    Yex.Nif.undo_manager_add_updated_observer(ref, observer_pid)
  end

  @doc """
  Adds an observer for stack item popped events.
  """
  @spec add_popped_observer(%__MODULE__{}, pid()) :: :ok | {:error, term()}
  def add_popped_observer(%__MODULE__{reference: ref}, observer_pid) do
    Yex.Nif.undo_manager_add_popped_observer(ref, observer_pid)
  end
end

defmodule Yex.UndoManager.Event do
  @type t :: %__MODULE__{
    meta: map(),
    stack_item_id: integer()
  }

  defstruct [:meta, :stack_item_id]
end

# Example usage in test
defmodule Yex.UndoManagerTest do
  use ExUnit.Case

  test "handles metadata updates in event callbacks" do
    doc = Yex.Doc.new()
    text = Yex.Text.new(doc)
    manager = Yex.UndoManager.new(doc, text)

    test_pid = self()

    # Add observer that updates metadata during the callback
    :ok = Yex.UndoManager.add_added_observer(manager, fn event ->
      # Update metadata directly in the callback
      event.meta["test"] = "value"
    end)

    # Make a change that will trigger an event
    Yex.Text.insert(text, 0, "abc")

    # Verify the metadata was updated during the event
    assert_receive {:stack_item_added, %Yex.UndoManager.Event{
      stack_item_id: _id,
      meta: %{"test" => "value"}
    }}
  end
end

def handle_undo_event(pid, event_type, data) do
  send(pid, {event_type, data})
end
