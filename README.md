# str

A tool for modifying streams, character by character.

## Examples

**Swap case**

    :L[32-][:U[32+][]#?]#?

or

    :L[#L][#U]#?

or

    #S

**Quine**

    `%r:#p;`:#p;
    `dro;`dro;
    `%rdp;`dp;
    `:O[:!;]o`:!;

**Truth machine**

    ::b'0=?u

Buffer the character, unbuffer it if its 0.

**Concatenate stack**

    v'+~Y#!