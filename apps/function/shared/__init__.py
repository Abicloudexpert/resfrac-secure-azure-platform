"""Business logic for the ResFrac Python Azure Function.

The logic is deliberately separated from the Azure Functions bindings
(``function_app.py``) so it can be unit-tested without the Functions host or
any Azure connectivity — dependencies (the storage client) are injected.
"""
