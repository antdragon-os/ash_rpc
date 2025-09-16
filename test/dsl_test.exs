defmodule AshRpc.DslTest.Resource do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshRpc]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string
  end

  actions do
    defaults [:read, :create, :update]

    read :get_by_email do
      argument :email, :string, allow_nil?: false
      get? true
    end

    create :register_with_password do
      accept [:email]
    end
  end

  trpc do
    query :read do
      sortable false
      relationships [:profile]
    end

    query :get_by_email, :get_by_email do
      filterable false
      selectable true
    end

    mutation :create do
      metadata fn _subject, _result, _ctx ->
        %{created: true}
      end
    end

    mutation :register, :register_with_password do
      metadata fn _subject, _result, _ctx ->
        %{registered: true}
      end
    end
  end
end

defmodule AshRpc.DslTest do
  use ExUnit.Case, async: true

  alias AshRpc.Dsl.Info
  alias AshRpc.Dsl.Procedure

  test "query block DSL configures procedure" do
    %Procedure{} = procedure = Info.find_procedure(AshRpc.DslTest.Resource, :read)

    assert procedure.method == :query
    assert procedure.action == :read
    refute procedure.sortable
    assert procedure.filterable
    assert procedure.relationships == [:profile]
  end

  test "query may override flags" do
    %Procedure{} = procedure = Info.find_procedure(AshRpc.DslTest.Resource, :get_by_email)

    refute procedure.filterable
    assert procedure.selectable
  end

  test "mutations default action to name" do
    %Procedure{} = procedure = Info.find_procedure(AshRpc.DslTest.Resource, :create)

    assert procedure.method == :mutation
    assert procedure.action == :create
    assert is_function(procedure.metadata, 3)
  end

  test "mutations support custom action names" do
    %Procedure{} = procedure = Info.find_procedure(AshRpc.DslTest.Resource, :register)

    assert procedure.action == :register_with_password
  end
end
