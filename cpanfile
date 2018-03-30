requires 'perl', '5.010';
requires 'Carp';

on test => sub {
  requires 'Test2' => '1.302125';
  requires 'Test2::Suite' => '0.000100';
  requires 'Test2::V0';
  requires 'Type::Tiny';
};
