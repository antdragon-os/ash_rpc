defmodule AshRpc.ErrorTest do
  use ExUnit.Case, async: true

  alias AshRpc.Error.Error

  test "builds trpc error for generic error" do
    err = %RuntimeError{message: "boom"}
    trpc = AshRpc.Error.Error.to_trpc_error(err)

    assert is_map(trpc)
    assert is_integer(trpc.code)
    assert is_binary(trpc.message)
    assert is_map(trpc.data)
    assert is_integer(trpc.data.httpStatus)
  end

  test "maps not found to 404 classification" do
    nf = Ash.Error.Query.NotFound.exception(resource: Ash.Resource, primary_key: [id: 1])
    trpc = Error.to_trpc_error(nf)

    assert 404 == trpc.data.httpStatus
    assert String.match?(trpc.message, ~r/not/i)
  end

  test "extracts form validation errors from Ash InvalidAttribute errors" do
    # Mock Ash validation errors
    username_error = %Ash.Error.Changes.InvalidAttribute{
      field: :username,
      message: "Username is already taken"
    }

    password_error = %Ash.Error.Changes.InvalidAttribute{
      field: :password,
      message: "Password must be at least 8 characters"
    }

    # Create an Ash error with these validation errors
    ash_error = %Ash.Error.Invalid{
      class: :invalid,
      errors: [username_error, password_error],
      path: []
    }

    # Test the ErrorBuilder directly
    error_response = AshRpc.Error.ErrorBuilder.build_error_response(ash_error)

    assert error_response.type == "ash_error"
    assert Map.has_key?(error_response, :form)
    assert error_response.form["username"] == ["Username is already taken"]
    assert error_response.form["password"] == ["Password must be at least 8 characters"]
  end

  test "handles mixed validation and non-validation errors gracefully" do
    username_error = %Ash.Error.Changes.InvalidAttribute{
      field: :username,
      message: "Username is required"
    }

    generic_error = %RuntimeError{message: "Something went wrong"}

    ash_error = %Ash.Error.Invalid{
      class: :invalid,
      errors: [username_error, generic_error],
      path: []
    }

    error_response = AshRpc.Error.ErrorBuilder.build_error_response(ash_error)

    assert error_response.type == "ash_error"
    assert Map.has_key?(error_response, :form)
    assert error_response.form["username"] == ["Username is required"]
    # The generic error should be in the details.errors array, not in form
    assert length(error_response.details.errors) == 2
  end

  test "cleans verbose ash error messages with breadcrumbs" do
    # Simulate the verbose error message format from your example
    verbose_error = %Ash.Error.Changes.InvalidAttribute{
      field: :email,
      message:
        "\nBread Crumbs:\n  > Error returned from: TodoApp.Accounts.User.register_with_password\n\n\nInvalid value provided for email: has already been taken.\n"
    }

    ash_error = %Ash.Error.Invalid{
      class: :invalid,
      errors: [verbose_error],
      path: []
    }

    error_response = AshRpc.Error.ErrorBuilder.build_error_response(ash_error)

    assert error_response.type == "ash_error"
    assert Map.has_key?(error_response, :form)
    assert error_response.form["email"] == ["has already been taken"]

    # Also verify that nested error details are clean
    assert length(error_response.details.errors) == 1
    assert error_response.details.errors |> hd() |> Map.get(:message) == "has already been taken"
  end

  test "returns frontend-friendly error structure with form errors at root level" do
    username_error = %Ash.Error.Changes.InvalidAttribute{
      field: :username,
      message: "Username is already taken"
    }

    ash_error = %Ash.Error.Invalid{
      class: :invalid,
      errors: [username_error],
      path: []
    }

    trpc_error = AshRpc.Error.Error.to_trpc_error(ash_error)

    # Verify the flattened structure for frontend consumption
    assert Map.has_key?(trpc_error.data, :formErrors)
    assert trpc_error.data.formErrors["username"] == ["Username is already taken"]

    # Verify generic message for form validation errors
    assert trpc_error.message == "Validation failed"

    # Verify details are still available for debugging but don't contain redundant form data
    assert Map.has_key?(trpc_error.data, :details)
    assert length(trpc_error.data.details) == 1

    # Details should not contain the form key (it's at the root level now)
    refute Map.has_key?(trpc_error.data.details |> hd(), :form)

    # But should still contain other debugging info
    assert Map.has_key?(trpc_error.data.details |> hd(), :details)
  end

  test "does not add form key when no validation errors present" do
    generic_error = %RuntimeError{message: "Something went wrong"}

    ash_error = %Ash.Error.Invalid{
      class: :invalid,
      errors: [generic_error],
      path: []
    }

    error_response = AshRpc.Error.ErrorBuilder.build_error_response(ash_error)
    trpc_error = AshRpc.Error.Error.to_trpc_error(ash_error)

    assert error_response.type == "ash_error"
    refute Map.has_key?(error_response, :form)
    refute Map.has_key?(trpc_error.data, :formErrors)
    assert length(error_response.details.errors) == 1

    # Message should be the original error message, not "Validation failed"
    # For non-form errors, we keep the original message
    assert trpc_error.message != "Validation failed"
  end
end
