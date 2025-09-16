defmodule AshRpc do
  @moduledoc """
  Spark DSL extension for exposing Ash resource actions over Ash RPC.

      use Ash.Resource, extensions: [AshRpc]

      ash_rpc do
        expose [:read, :register_with_password]
        # optional: resource segment override
        # resource_name "user"
      end
  """
  @query %Spark.Dsl.Entity{
    name: :query,
    describe: "Expose an action as an Ash RPC query with advanced features",
    examples: [
      "query :list, :read",
      """
      query :read do
        filterable false
        selectable true
      end
      """
    ],
    args: [:name, {:optional, :action}],
    schema: [
      name: [type: :atom, required: true],
      action: [type: :atom, required: false],
      metadata: [
        type: {:fun, 3},
        required: false,
        doc:
          "A function to generate arbitrary metadata for the tRPC response: fn subject, result, ctx -> map end",
        snippet: "fn ${1:subject}, ${2:result}, ${3:ctx} -> $4 end"
      ],
      filterable: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Allow client-side filtering on this query"
      ],
      sortable: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Allow client-side sorting on this query"
      ],
      selectable: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Allow client-side field selection on this query"
      ],
      paginatable: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Allow client-side pagination on this query"
      ],
      relationships: [
        type: {:list, :atom},
        required: false,
        doc: "List of relationships that can be loaded: [:comments, :author]"
      ]
    ],
    target: AshRpc.Dsl.Procedure,
    auto_set_fields: [method: :query],
    transform: {AshRpc.Dsl.Procedure, :transform, []}
  }

  @mutation %Spark.Dsl.Entity{
    name: :mutation,
    describe: "Expose an action as an Ash RPC mutation with a custom procedure name",
    examples: [
      "mutation :register, :register_with_password",
      """
      mutation :register, :register_with_password do
        metadata fn _subject, user, _ctx ->
          %{token: user.__metadata__.token}
        end
      end
      """
    ],
    args: [:name, {:optional, :action}],
    schema: [
      name: [type: :atom, required: true],
      action: [type: :atom, required: false],
      metadata: [
        type: {:fun, 3},
        required: false,
        doc:
          "A function to generate arbitrary metadata for the tRPC response: fn subject, result, ctx -> map end",
        snippet: "fn ${1:subject}, ${2:result}, ${3:ctx} -> $4 end"
      ]
    ],
    target: AshRpc.Dsl.Procedure,
    auto_set_fields: [method: :mutation],
    transform: {AshRpc.Dsl.Procedure, :transform, []}
  }

  use Spark.Dsl.Extension,
    sections: [
      %Spark.Dsl.Section{
        name: :ash_rpc,
        describe: "Ash RPC exposure configuration",
        schema: [
          expose: [
            type: {:or, [:atom, {:list, :atom}]},
            doc: "Actions to expose (:all or a list of action names)",
            default: []
          ],
          methods: [
            type: :keyword_list,
            doc:
              "Optional per-action method overrides, e.g. [read: :mutation, register_with_password: :query]. Values: :query | :mutation",
            default: []
          ],
          resource_name: [
            type: :string,
            doc: "Optional path segment override for this resource"
          ]
        ],
        entities: [@query, @mutation]
      }
    ]
end
