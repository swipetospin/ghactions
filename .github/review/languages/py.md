## Python-specific checks

### PEP8 & idiomatic style (Minor)

Code should follow PEP8 and use Pythonic idioms — context managers,
comprehensions, and built-ins.

Bad:
```python
f = open("data.txt")
lines = f.readlines()
f.close()
```

Good:
```python
with open("data.txt") as f:
    lines = f.readlines()
```

### String formatting (Minor)

Prefer f-strings over `%`-formatting or `.format()` when the template
string is written inline. Do not flag `%`-formatting in logging calls
(`logger.info("%s", value)`), where it defers building the string until
the message is actually emitted, or `.format()`/`%` applied to a template
that is only known at runtime (e.g. loaded from a config file or an i18n
catalog) — an f-string cannot do either of those.

Bad:
```python
message = "User %s has %d items" % (user.name, count)
```

Good:
```python
message = f"User {user.name} has {count} items"
```

### Mutable default arguments (Blocking)

A mutable default argument is created once and shared across every call,
not recreated per call. This is a bug, not a style choice. The same applies
to any default computed at definition time, such as
`def f(ts=datetime.now())`, which freezes the timestamp at import.

Bad:
```python
def add_item(item, items=[]):
    items.append(item)
    return items
```

Good:
```python
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

### Broad exception handling (Blocking)

A bare `except:` or `except Exception:` that swallows the error hides real
bugs. Flag it unless the code logs or re-raises, or the broad catch is
clearly intentional (e.g. a top-level handler that must not crash the
process).

Bad:
```python
try:
    process(item)
except Exception:
    pass
```

Good:
```python
try:
    process(item)
except Exception:
    logger.exception("Failed to process %s", item)
    raise
```

### Silently passed exceptions (Minor)

Is an exception passed silently — even a narrow, specific one? This is
rarely correct on its own, regardless of how specific the except clause
is. Question every instance. If the developer really means to ignore the
exception, it needs a comment explaining why that's safe.

Bad:
```python
try:
    os.remove(path)
except FileNotFoundError:
    pass
```

Good:
```python
try:
    os.remove(path)
except FileNotFoundError:
    pass  # already removed by a concurrent cleanup job; nothing to do
```

### Late-binding closures (Blocking)

A lambda or nested function defined in a loop captures the variable, not
its value. Every closure sees the value from the last iteration.

Bad:
```python
handlers = [lambda: print(i) for i in range(3)]
```

Good:
```python
handlers = [lambda i=i: print(i) for i in range(3)]
```

### Identity vs. equality (Blocking)

Use `is` only for `None`, `True`, `False`, and sentinel objects. Comparing
strings or numbers with `is` depends on interning and fails unpredictably.

Bad:
```python
if status is "active":
    activate(user)
```

Good:
```python
if status == "active":
    activate(user)
```

### Mutating a collection while iterating over it (Blocking)

Adding or removing items from a list, dict, or set inside a loop over that
same collection skips items or raises `RuntimeError`. Iterate over a copy
or build a new collection.

Bad:
```python
for key in cache:
    if cache[key].expired:
        del cache[key]
```

Good:
```python
cache = {k: v for k, v in cache.items() if not v.expired}
```

### Falsy checks on valid values (Blocking)

`if not value:` treats `0`, `""`, and `[]` the same as `None`. Flag it only
when one of those is a valid value in context.

Bad:
```python
def set_discount(percent=None):
    if not percent:
        percent = DEFAULT_DISCOUNT  # a 0% discount is silently replaced
```

Good:
```python
def set_discount(percent=None):
    if percent is None:
        percent = DEFAULT_DISCOUNT
```

### Network calls without a timeout (Blocking)

`requests` and `httpx` calls with no `timeout` can hang forever and block
the worker.

Bad:
```python
response = requests.get(url)
```

Good:
```python
response = requests.get(url, timeout=10)
```

### Python-specific security (Blocking)

Flag these when they touch untrusted input:

- `subprocess` with `shell=True` and interpolated values.
- `pickle.loads` or `pickle.load`.
- `yaml.load` without `Loader=yaml.SafeLoader` (or use `yaml.safe_load`).
- `eval` or `exec`.
- SQL built with f-strings, `%`, or `.format()` instead of query parameters.

Bad:
```python
cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")
```

Good:
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```
