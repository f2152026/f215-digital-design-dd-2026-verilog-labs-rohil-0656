// FA_Gate.v -- Part (b): gates reordered (no delays yet).
module FA_Gate(
  input  a,
  input  b,
  input  cin,
  output sum,
  output cout
);
  wire ps, pc1, pc2;

  or  (cout, pc1, pc2);
  and (pc2, cin, ps);
  xor (sum, cin, ps);
  and (pc1, a,   b);
  xor (ps,  a,   b);

endmodule
