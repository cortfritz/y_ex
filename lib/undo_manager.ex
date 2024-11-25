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

defmodule Yex.UndoManager do
  alias Yex.UndoManager.Options

  @moduledoc """
  Represents a Y.UndoManager instance.
  """
  defstruct [:reference]

  @type t :: %__MODULE__{
    reference: reference()
  }

  @doc """
  Creates a new UndoManager for the given document and scope with default options.
  The scope can be a Text, Array, or Map type.
  """
  def new(doc, %Yex.Text{} = scope) do
    new_with_options(doc, scope, %Options{})
  end

  def new(doc, %Yex.Array{} = scope) do
    new_with_options(doc, scope, %Options{})
  end

  def new(doc, %Yex.Map{} = scope) do
    new_with_options(doc, scope, %Options{})
  end

  @doc """
  Creates a new UndoManager with the given options.

  ## Options

  See `Yex.UndoManager.Options` for available options.
  """
  def new_with_options(doc, %Yex.Text{} = scope, %Options{} = options) do
    case Yex.Nif.undo_manager_new_with_options(doc, {:text, scope}, options) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  def new_with_options(doc, %Yex.Array{} = scope, %Options{} = options) do
    case Yex.Nif.undo_manager_new_with_options(doc, {:array, scope}, options) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  def new_with_options(doc, %Yex.Map{} = scope, %Options{} = options) do
    case Yex.Nif.undo_manager_new_with_options(doc, {:map, scope}, options) do
      {:ok, manager} -> manager
      error -> error
    end
  end

  @doc """
  Includes an origin to be tracked by the UndoManager.
  """
  def include_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_include_origin(undo_manager, origin)
  end

  @doc """
  Excludes an origin from being tracked by the UndoManager.
  """
  def exclude_origin(undo_manager, origin) do
    Yex.Nif.undo_manager_exclude_origin(undo_manager, origin)
  end

  @doc """
  Undoes the last tracked change.
  """
  def undo(undo_manager) do
    Yex.Nif.undo_manager_undo(undo_manager)
  end

  @doc """
  Redoes the last undone change.
  """
  def redo(undo_manager) do
    Yex.Nif.undo_manager_redo(undo_manager)
  end

  @doc """
  Expands the scope of the UndoManager to include additional shared types.
  The scope can be a Text, Array, or Map type.
  """
  def expand_scope(undo_manager, %Yex.Text{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:text, scope})
  end

  def expand_scope(undo_manager, %Yex.Array{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:array, scope})
  end

  def expand_scope(undo_manager, %Yex.Map{} = scope) do
    Yex.Nif.undo_manager_expand_scope(undo_manager, {:map, scope})
  end

  @doc """
  Stops capturing changes for the current stack item.
  This ensures that the next change will create a new stack item instead of
  being merged with the previous one, even if it occurs within the normal timeout window.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "a")
      UndoManager.stop_capturing(undo_manager)
      Text.insert(text, 1, "b")
      UndoManager.undo(undo_manager)
      # Text.to_string(text) will be "a" (only "b" was removed)
  """
  def stop_capturing(undo_manager) do
    Yex.Nif.undo_manager_stop_capturing(undo_manager)
  end

  @doc """
  Adds an observer to the UndoManager that will receive callbacks when
  stack items are added or popped.

  ## Example:
      defmodule MyObserver do
        @behaviour Yex.UndoManager.Observer

        def handle_stack_item_added(stack_item) do
          {:ok, Map.put(stack_item.meta, :cursor_position, get_cursor_position())}
        end

        def handle_stack_item_popped(stack_item) do
          restore_cursor_position(stack_item.meta.cursor_position)
          :ok
        end
      end

      undo_manager = UndoManager.new(doc, text)
      UndoManager.add_observer(undo_manager, MyObserver)
  """
  def add_observer(undo_manager, observer) when is_atom(observer) do
    {:ok, pid} = Yex.UndoServer.start_link(undo_manager: undo_manager, module: observer)
    pid
  end

  @doc """
  Clears all StackItems stored within current UndoManager, effectively resetting its state.

  ## Example:
      text = Doc.get_text(doc, "text")
      undo_manager = UndoManager.new(doc, text)

      Text.insert(text, 0, "Hello")
      Text.insert(text, 5, " World")
      UndoManager.clear(undo_manager)
      # All undo/redo history is now cleared
  """
  def clear(undo_manager) do
    Yex.Nif.undo_manager_clear(undo_manager)
  end
end
