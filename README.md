# str

A tool for modifying streams, character by character.

## Examples

**Swap case**

    :L[32-][:U[32+][]#?]#?

or

    :L[#L][#U]#?

or

    #S

**Quines**

    `dro;`dro;
    `%rdp;`dp;
    `dr[d!;]o`d!;

**Truth machine**

    ddb'0=?u

or

    ddbMN?u

Buffer the character, unbuffer it if its 0.

**Concatenate stack**

    v'+~Y#!