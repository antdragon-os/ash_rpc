defmodule AshRpc.TypeScript.TypeInference do
  @moduledoc """
  Contains all the TypeScript utility types for type inference and field selection.
  """

  @doc """
  Returns the complete utility types for TypeScript type inference.
  """
  def utility_types do
    """
    type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (
      k: infer I,
    ) => void
      ? I
      : never;

    type HasComplexFields<T extends {__type: string; __primitiveFields: string}> = keyof Omit<
      T,
      "__primitiveFields" | "__type"
    > extends never
      ? false
      : true;

    // Allow leading + / - on string field names for include/exclude semantics
    type WithModifiers<T> = T extends string ? T | `+${T}` | `-${T}` : T;

    type LeafFieldSelection<T extends {__type: string; __primitiveFields: string}> = T["__primitiveFields"];

    type ComplexFieldSelection<T extends {__type: string; __primitiveFields: string}> = {
      [K in keyof Omit<T, "__primitiveFields" | "__type" | T["__primitiveFields"]>]?: T[K] extends {
        __type: "Relationship";
        __resource: infer Resource;
      }
        ? NonNullable<Resource> extends {__type: string; __primitiveFields: string}
          ? UnifiedFieldSelection<NonNullable<Resource>>[]
          : never
        : T[K] extends {
              __type: "ComplexCalculation";
              __returnType: infer ReturnType;
            }
          ? T[K] extends { __args: any }
            ? NonNullable<ReturnType> extends {__type: string; __primitiveFields: string}
              ? {
                  args: T[K]["__args"];
                  fields: UnifiedFieldSelection<NonNullable<ReturnType>>[];
                }
              : { args: T[K]["__args"] }
            : NonNullable<ReturnType> extends {__type: string; __primitiveFields: string}
              ? { fields: UnifiedFieldSelection<NonNullable<ReturnType>>[] }
              : never
          : NonNullable<T[K]> extends {__type: string; __primitiveFields: string}
            ? UnifiedFieldSelection<NonNullable<T[K]>>[]
            : never;
    };

    type UnifiedFieldSelection<T extends {__type: string; __primitiveFields: string}> =
      HasComplexFields<T> extends false
        ? LeafFieldSelection<T>
        : LeafFieldSelection<T> | ComplexFieldSelection<T>;

    type InferFieldValue<
      T extends {__type: string; __primitiveFields: string},
      Field,
    > = Field extends T["__primitiveFields"]
      ? Field extends keyof T
        ? { [K in Field]: T[Field] }
        : never
      : Field extends Record<string, any>
        ? {
            [K in keyof Field]: K extends keyof T
              ? T[K] extends {
                  __type: "Relationship";
                  __resource: infer Resource;
                }
                ? NonNullable<Resource> extends {__type: string; __primitiveFields: string}
                  ? T[K] extends { __array: true }
                    ? Array<InferSelectedResult<NonNullable<Resource>, Field[K]>>
                    : null extends Resource
                      ? InferSelectedResult<NonNullable<Resource>, Field[K]> | null
                      : InferSelectedResult<NonNullable<Resource>, Field[K]>
                : never
              : T[K] extends {
                    __type: "ComplexCalculation";
                    __returnType: infer ReturnType;
                  }
                ? NonNullable<ReturnType> extends {__type: string; __primitiveFields: string}
                  ? null extends ReturnType
                    ? InferSelectedResult<NonNullable<ReturnType>, Field[K]["fields"]> | null
                    : InferSelectedResult<NonNullable<ReturnType>, Field[K]["fields"]>
                  : ReturnType
                : NonNullable<T[K]> extends {__type: string; __primitiveFields: string}
                  ? null extends T[K]
                    ? InferSelectedResult<NonNullable<T[K]>, Field[K]> | null
                    : InferSelectedResult<NonNullable<T[K]>, Field[K]>
                  : never
              : never;
          }
        : never;

    type InferResult<
      T extends {__type: string; __primitiveFields: string},
      SelectedFields extends UnifiedFieldSelection<T>[],
    > = UnionToIntersection<
      {
        [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
      }[number]
    >;

    type InferSelectedResult<
      T extends {__type: string; __primitiveFields: string},
      SelectedFields extends UnifiedFieldSelection<T>[],
    > = UnionToIntersection<
      {
        [K in keyof SelectedFields]: InferFieldValue<T, SelectedFields[K]>;
      }[number]
    >;

    // Advanced Query Types
    /**
     * Filter operators supported on simple fields.
     */
    export type AshFieldOps<T> = T | { eq?: T; neq?: T; gt?: T; lt?: T; gte?: T; lte?: T };
    /**
     * Filter expression supporting boolean logic and per-field operators.
     */
    export type AshFilter<Shape> = Partial<{ [K in keyof Shape]: AshFieldOps<Shape[K]> }> & {
      and?: AshFilter<Shape>[];
      or?: AshFilter<Shape>[];
      not?: AshFilter<Shape>;
    };
    /** Sorting direction */
    export type AshSortDirection = 'asc' | 'desc';
    /** Sort type – either a list of field:direction maps or a single map */
    export type AshSort = Array<Record<string, AshSortDirection>> | Record<string, AshSortDirection>;
    /** Unified select – supports strings with +/- and nested relationships */
    export type AshSelect = (string | Record<string, any>)[];
    /**
     * Flexible pagination type supporting both offset and keyset strategies
     * Backend automatically detects strategy based on provided fields:
     * - type: "offset" + offset/limit -> offset pagination
     * - type: "keyset" + after/before -> keyset pagination
     * - offset present -> auto-detect as offset
     * - after/before present -> auto-detect as keyset
     * - default -> keyset pagination
     */
    export type AshPage = {
      /** Pagination strategy (optional - backend auto-detects if not specified) */
      type?: "offset" | "keyset";
      /** Number of items per page (default: 20) */
      limit?: number;

      /** Offset pagination fields */
      /** Number of items to skip (use with offset pagination) */
      offset?: number;
      /** Page number (1-based, alternative to offset) */
      page?: number;

      /** Keyset pagination fields */
      /** Cursor to start after (use with keyset pagination) */
      after?: AshCursor;
      /** Cursor to start before (use with keyset pagination) */
      before?: AshCursor;

      /** Whether to include total count (works with both strategies) */
      count?: boolean;
    };

    /** Cursor value for pagination */
    export type AshCursor = string;

    /** Load relationships (deprecated in favor of fields nesting; still supported) */
    export type AshLoad = string[];

    /**
     * Query input options for useQuery()
     * Supports both offset and keyset pagination
     */
    export interface AshQueryInput<Shape = Record<string, unknown>> {
      filter?: AshFilter<Shape>;
      sort?: AshSort;
      select?: AshSelect;
      page?: AshPage;
      load?: AshLoad;
      cursor?: AshCursor;
    }

    /**
     * Query input options for useInfiniteQuery()
     * Only supports keyset pagination
     */
    export interface AshInfiniteQueryInput<Shape = Record<string, unknown>> {
      filter?: AshFilter<Shape>;
      sort?: AshSort;
      select?: AshSelect;
      page?: AshKeysetPage;
      load?: AshLoad;
      cursor?: AshCursor;
    }

    /**
     * Standard query response without pagination
     */
    export interface AshQueryResponse<T = unknown> {
      result: T;
      meta: Record<string, unknown>;
    }

    /**
     * Response for useQuery() with offset pagination
     * Supports traditional page-based navigation with count
     */
    export interface AshOffsetQueryResponse<T = unknown> {
      result: T;
      meta: {
        /** Current page limit */
        limit: number;
        /** Current page offset */
        offset: number;
        /** Whether there are more results */
        hasMore: boolean;
        /** Whether there is a previous page */
        hasPrevious: boolean;
        /** Current page number (1-based) */
        currentPage: number;
        /** Next page number (if available) */
        nextPage?: number | null;
        /** Previous page number (if available) */
        previousPage?: number | null;
        /** Total pages (when count is requested) */
        totalPages?: number | null;
        /** Total count (when requested) */
        count?: number | null;
        /** Pagination type discriminator */
        type: 'offset';
      } & Record<string, unknown>;
    }

    /**
     * Response for useInfiniteQuery() with cursor pagination
     * Supports infinite scrolling with cursor-based navigation
     */
    export interface AshInfiniteQueryResponse<T = unknown> {
      result: T;
      meta: {
        /** Current page limit */
        limit: number;
        /** Cursor for next page (if available) */
        nextCursor?: AshCursor;
        /** Whether there are more pages */
        hasNextPage: boolean;
        /** Pagination type discriminator */
        type: 'keyset';
      } & Record<string, unknown>;
    }

    /**
     * Unified paginated response - supports both pagination types
     * Used for read actions that can return either pagination type
     */
    export interface AshPaginatedQueryResponse<T = unknown> {
      result: T;
      meta: {
        /** Current page limit */
        limit: number;

        /** Offset pagination fields */
        offset?: number;
        hasMore?: boolean;
        hasPrevious?: boolean;
        currentPage?: number;
        nextPage?: number | null;
        previousPage?: number | null;
        totalPages?: number | null;
        count?: number | null;

        /** Keyset pagination fields */
        nextCursor?: AshCursor;
        hasNextPage?: boolean;

        /** Type discriminator */
        type: 'offset' | 'keyset';
      } & Record<string, unknown>;
    }
    """
  end
end
