///|
/// 算术值：整数或浮点数。
priv enum Arith {
  AInt(Int64)
  AFloat(Double)
}

///|
fn arith_to_double(a : Arith) -> Double {
  match a {
    Arith::AInt(x) => x.to_double()
    Arith::AFloat(x) => x
  }
}

///|
fn arith_compare(a : Arith, b : Arith) -> Int {
  match (a, b) {
    (Arith::AInt(x), Arith::AInt(y)) => x.compare(y)
    _ => {
      let x = arith_to_double(a)
      let y = arith_to_double(b)
      if x < y {
        -1
      } else if x > y {
        1
      } else {
        0
      }
    }
  }
}

///|
fn arith_add(a : Arith, b : Arith) -> Arith {
  match (a, b) {
    (Arith::AInt(x), Arith::AInt(y)) => Arith::AInt(x + y)
    _ => Arith::AFloat(arith_to_double(a) + arith_to_double(b))
  }
}

///|
fn arith_sub(a : Arith, b : Arith) -> Arith {
  match (a, b) {
    (Arith::AInt(x), Arith::AInt(y)) => Arith::AInt(x - y)
    _ => Arith::AFloat(arith_to_double(a) - arith_to_double(b))
  }
}

///|
fn arith_mul(a : Arith, b : Arith) -> Arith {
  match (a, b) {
    (Arith::AInt(x), Arith::AInt(y)) => Arith::AInt(x * y)
    _ => Arith::AFloat(arith_to_double(a) * arith_to_double(b))
  }
}

///|
fn arith_div(a : Arith, b : Arith) -> Arith {
  Arith::AFloat(arith_to_double(a) / arith_to_double(b))
}

///|
/// 整数地板除。
fn int_floor_div(x : Int64, y : Int64) -> Int64? {
  if y == 0L {
    return None
  }
  let q = x / y
  let r = x % y
  if r != 0L && (r < 0L) != (y < 0L) {
    Some(q - 1L)
  } else {
    Some(q)
  }
}

///|
/// 整数地板模。
fn int_mod(x : Int64, y : Int64) -> Int64? {
  if y == 0L {
    return None
  }
  let r = x % y
  if r != 0L && (r < 0L) != (y < 0L) {
    Some(r + y)
  } else {
    Some(r)
  }
}

///|
fn int_pow(x : Int64, y : Int64) -> Int64 {
  let mut acc = 1L
  let mut base = x
  let mut exp = y
  while exp > 0L {
    if exp % 2L == 1L {
      acc = acc * base
    }
    base = base * base
    exp = exp / 2L
  }
  acc
}

///|
/// 求值算术表达式；失败返回 None（运算错误或不可求值）。
fn eval_arith(subst : Subst, t : LoveTerm) -> Arith? {
  match subst.deref(t) {
    LoveTerm::Int(x) => Some(Arith::AInt(x))
    LoveTerm::Float(x) => Some(Arith::AFloat(x))
    LoveTerm::Atom("pi") => Some(Arith::AFloat(@math.PI))
    LoveTerm::Struct(name, args) => eval_op(subst, name, args)
    _ => None
  }
}

///|
fn eval_op(subst : Subst, name : String, args : Array[LoveTerm]) -> Arith? {
  match name {
    "+" => bin2(subst, args, arith_add)
    "-" =>
      if args.length() == 1 {
        unary(subst, args[0], fn(a : Arith) {
          match a {
            Arith::AInt(x) => Arith::AInt(-x)
            Arith::AFloat(x) => Arith::AFloat(-x)
          }
        })
      } else {
        bin2(subst, args, arith_sub)
      }
    "*" => bin2(subst, args, arith_mul)
    "/" => bin2(subst, args, arith_div)
    "//" => {
      let a = eval_arith(subst, args[0])
      let b = eval_arith(subst, args[1])
      match (a, b) {
        (Some(Arith::AInt(x)), Some(Arith::AInt(y))) =>
          match int_floor_div(x, y) {
            Some(q) => Some(Arith::AInt(q))
            None => None
          }
        _ => None
      }
    }
    "div" => {
      let a = eval_arith(subst, args[0])
      let b = eval_arith(subst, args[1])
      match (a, b) {
        (Some(Arith::AInt(x)), Some(Arith::AInt(y))) =>
          if y == 0L {
            None
          } else {
            Some(Arith::AInt(x / y))
          }
        _ => None
      }
    }
    "rem" => {
      let a = eval_arith(subst, args[0])
      let b = eval_arith(subst, args[1])
      match (a, b) {
        (Some(Arith::AInt(x)), Some(Arith::AInt(y))) =>
          if y == 0L {
            None
          } else {
            Some(Arith::AInt(x % y))
          }
        _ => None
      }
    }
    "mod" => {
      let a = eval_arith(subst, args[0])
      let b = eval_arith(subst, args[1])
      match (a, b) {
        (Some(Arith::AInt(x)), Some(Arith::AInt(y))) =>
          match int_mod(x, y) {
            Some(r) => Some(Arith::AInt(r))
            None => None
          }
        _ => None
      }
    }
    "^" => {
      let a = eval_arith(subst, args[0])
      let b = eval_arith(subst, args[1])
      match (a, b) {
        (Some(Arith::AInt(x)), Some(Arith::AInt(y))) =>
          if y >= 0L {
            Some(Arith::AInt(int_pow(x, y)))
          } else {
            Some(Arith::AFloat(@math.pow(x.to_double(), y.to_double())))
          }
        (Some(x), Some(y)) =>
          Some(Arith::AFloat(@math.pow(arith_to_double(x), arith_to_double(y))))
        _ => None
      }
    }
    "\\" =>
      if args.length() == 1 {
        match eval_arith(subst, args[0]) {
          Some(Arith::AInt(x)) => Some(Arith::AInt(x.lnot()))
          _ => None
        }
      } else {
        None
      }
    "abs" =>
      unary(subst, args[0], fn(a : Arith) {
        match a {
          Arith::AInt(x) => Arith::AInt(x.abs())
          Arith::AFloat(x) => Arith::AFloat(x.abs())
        }
      })
    "sign" =>
      unary(subst, args[0], fn(a : Arith) {
        match a {
          Arith::AInt(x) =>
            Arith::AInt(if x > 0L { 1L } else if x < 0L { -1L } else { 0L })
          Arith::AFloat(x) =>
            Arith::AFloat(
              if x > 0.0 {
                1.0
              } else if x < 0.0 {
                -1.0
              } else {
                0.0
              },
            )
        }
      })
    "max" =>
      bin2(subst, args, fn(a : Arith, b : Arith) {
        if arith_compare(a, b) >= 0 {
          a
        } else {
          b
        }
      })
    "min" =>
      bin2(subst, args, fn(a : Arith, b : Arith) {
        if arith_compare(a, b) <= 0 {
          a
        } else {
          b
        }
      })
    "sqrt" => unary_float(subst, args[0], fn(x : Double) { x.sqrt() })
    "exp" => unary_float(subst, args[0], @math.exp)
    "log" => unary_float(subst, args[0], @math.ln)
    "sin" => unary_float(subst, args[0], @math.sin)
    "cos" => unary_float(subst, args[0], @math.cos)
    "tan" => unary_float(subst, args[0], @math.tan)
    "floor" => unary_float(subst, args[0], @math.floor)
    "ceiling" => unary_float(subst, args[0], @math.ceil)
    "round" => unary_float(subst, args[0], @math.round)
    "truncate" => unary_float(subst, args[0], @math.trunc)
    "float" =>
      unary(subst, args[0], fn(a : Arith) { Arith::AFloat(arith_to_double(a)) })
    "integer" =>
      unary(subst, args[0], fn(a : Arith) {
        match a {
          Arith::AInt(x) => Arith::AInt(x)
          Arith::AFloat(x) => Arith::AInt(x.to_int64())
        }
      })
    _ => None
  }
}

///|
fn unary(subst : Subst, t : LoveTerm, f : (Arith) -> Arith) -> Arith? {
  match eval_arith(subst, t) {
    Some(a) => Some(f(a))
    None => None
  }
}

///|
fn unary_float(subst : Subst, t : LoveTerm, f : (Double) -> Double) -> Arith? {
  match eval_arith(subst, t) {
    Some(a) => Some(Arith::AFloat(f(arith_to_double(a))))
    None => None
  }
}

///|
fn bin2(
  subst : Subst,
  args : Array[LoveTerm],
  f : (Arith, Arith) -> Arith,
) -> Arith? {
  if args.length() != 2 {
    return None
  }
  match (eval_arith(subst, args[0]), eval_arith(subst, args[1])) {
    (Some(a), Some(b)) => Some(f(a, b))
    _ => None
  }
}
