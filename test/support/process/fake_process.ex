defmodule Helix.Test.Process do

  import Helix.Process

  process FakeFileTransfer do

    alias HELL.TestHelper.Random

    process_struct [:file_id]

    def new do
      %__MODULE__{
        file_id: Random.number()
      }
    end

    def new(%{file_id: file_id}) do
      %__MODULE__{
        file_id: file_id
      }
    end

    processable do
      on_completion(_process, _data) do
        {:delete, []}
      end
    end

    resourceable do

      @type params :: term
      @type factors :: term

      get_factors(_) do
        :noop
      end

      dlk(%{type: :download}) do
        100
      end

      ulk(%{type: :upload}) do
        100
      end

      dlk(%{type: :upload})
      ulk(%{type: :download})

      def dynamic(%{type: :download}) do
        [:dlk]
      end

      def dynamic(%{type: :upload}) do
        [:ulk]
      end
    end

    executable do

      @type params :: term
      @type meta :: term

      resources(_, _, _, _) do
        %{}
      end
    end
  end

  process FakeDefaultProcess do

    process_struct [:foo]

    def new do
      %__MODULE__{
        foo: :bar
      }
    end

    # Inherits default Processable callbacks
    processable do
      on_completion(_process, _data) do
        {:delete, []}
      end
    end

    resourceable do

      @type params :: term
      @type factors :: term

      get_factors(_) do
        :noop
      end

      cpu(_) do
        5000
      end

      def dynamic(_) do
        [:cpu]
      end
    end

    executable do

      @type params :: term
      @type meta :: term

      resources(_, _, _, _) do
        %{}
      end
    end
  end
end
