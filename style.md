
## Progamming Style 

- Data Oriented Programming


## Rules & Quality

### Explicit Limits

Put a limit on everything because everything has a limit.
Bound all resources, concurrency, and execution. Don’t react to stimuli but use fixed intervals to schedule work. Avoid recursion. Bound loops and queues to detect infinite loops and latency spikes.
Use fixed types like u32. Avoid architecture-specific types like usize.

### Strong Types

Use the strongest type that fits, so the compiler rejects mistakes before assertions have to.

    Use an enum instead of an integer for a closed set of values (Month, Weekday)
    Use a distinct type instead of a bare integer for a quantity with a unit or meaning (Epoch_Day, Year)
    Use a struct instead of two parallel integers that only make sense together (Instant)
    Use a bit_set instead of integer flags
    Do not mix units in one type: wall clock time and monotonic time are different types
    Convert between types explicitly in one place, never implicitly at the call site

Bare integers are for counts and arithmetic, not for identities.

### Assertions

Where types check structure, assertions check all logic and state, to detect programmer error, multiply fuzzing, and downgrade catastrophe. Assert arguments, returns, and invariants: what you expect and don't expect, the positive and negative space, not only contract but breach.


### Logical Interfaces

The safety (as well as performance and experience) of a system is dominated by the quality of its interfaces.

    Minimize public API surface area
    Define fault models
    Abstract physical non-deterministic interfaces with logical deterministic interfaces
    Push control flow up and data flow down

### Dimensionality

Simplify function signatures to minimize branches at the call site, which are viral through the call graph.

As a return type, bool trumps u64 trumps !u64.

Minimize or define variables near to when/where they are used, to close semantic gaps in time/space.

### Zero Dependencies

Dependencies risk safety and performance, invite supply chain attacks, and increase install times. For infrastructure in particular, these costs multiply up the stack.

The Odin `base:` and `core:` packages ship with the compiler and are allowed (`base:intrinsics`, `core:fmt`, `core:io`, `core:os`, `core:strings` and so on). Nothing else is: no `vendor:`, no third party packages. The one exception is `core:time`, because this library exists to provide dates and times without it.

Similarly, tools have costs. A small standard toolbox feels slow for you at first but accelerates the team long term.

### Zero Technical Debt

Code, like steel, is easier to change while it's hot. Do it right the first time, the best you know how, because you may not get another chance, and because quality builds momentum. This is the only way to make steady progress, knowing that the foundations are solid.

### Simplicity And Elegance

    “...simple and elegant systems tend to be easier and faster to design and get right, more efficient in execution, and much more reliable, [but] require hard work and discipline to achieve…”

— Edsger Dijkstra


### Nouns And Verbs

Great names are the essence of great code, capturing what a thing is or does, for a crisp mental model.

    Append qualifiers to names
    Sort by most significant word (big endian naming)
    Use the same number of characters for related names (e.g. source/target) so they line up in the source.
    Use snake_case for procs, variables, and enum members
    Use CAPITAL_SNAKE_CASE for constants
    Use Ada_Case for types (structs, enums, unions, bit_sets), as the Odin core library does
    Don't abbreviate

### Formatted Output

Odin's `core:fmt` names its formatting procs by where the output goes and who owns the memory. Only add formatting when it is needed, but when it is, support the whole family, so callers choose by destination and allocation without hitting a gap.

    aprint   Returns a formatted string. Allocates using the provided allocator
    bprint   Returns a formatted string backed by a supplied buffer. Writes into the buffer
    caprint  Returns a formatted C string. Allocates using the provided allocator
    eprint   Writes to os.stderr with the default print settings
    fprint   Writes to a ^os.File with the default print settings
    print    Writes to os.stdout with the default print settings
    sbprint  Writes to the given strings.Builder with the default print settings
    tprint   Returns a formatted string. Allocates using the context's temporary allocator
    wprint   Writes to an io.Writer with the default print settings

### File Order

Order each file as: enums and constants, then structs (props), then procs.

Start each section with a marker: a 76 character `=` rule, a `<kind>: <name>` line, and another rule. The kind is lowercase (`constants`, `enums`, `types`, `structs`, `procs`). After the colon goes a short lowercase comment saying what the section is about, not a list of the names inside it, because a list grows with the section.

    // ============================================================================
    // procs: local_date
    // ============================================================================

