/*
 * Exercises the paths the NativeScript runtimes depend on: ffi_call with
 * scalars, a homogeneous floating-point aggregate and a vector, and a closure
 * allocated through ffi_closure_alloc (the trampoline-table allocator on
 * arm64 Apple targets).
 */
#include <ffi.h>
#include <stdio.h>
#include <string.h>

typedef struct { double x, y, w, h; } Rect;
typedef float float4 __attribute__((ext_vector_type(4)));

static int add(int a, int b) { return a + b; }
static double area(Rect r) { return r.w * r.h; }
static float4 scale(float4 v, float s) { return v * s; }

static void double_it(ffi_cif *cif, void *ret, void **args, void *user_data) {
  (void)cif;
  *(ffi_arg *)ret = *(int *)args[0] * 2 + *(int *)user_data;
}

static int failures;
#define CHECK(cond, what) \
  do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", what); failures++; } } while (0)

int main(void) {
  ffi_cif cif;

  ffi_type *int_args[2] = {&ffi_type_sint, &ffi_type_sint};
  CHECK(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint, int_args) == FFI_OK, "prep add");
  int a = 2, b = 3;
  void *add_values[2] = {&a, &b};
  ffi_arg sum = 0;
  ffi_call(&cif, FFI_FN(add), &sum, add_values);
  CHECK((int)sum == 5, "call add");

  ffi_type *rect_elements[5] = {&ffi_type_double, &ffi_type_double, &ffi_type_double,
                                &ffi_type_double, NULL};
  ffi_type rect_type;
  memset(&rect_type, 0, sizeof rect_type);
  rect_type.type = FFI_TYPE_STRUCT;
  rect_type.elements = rect_elements;
  ffi_type *rect_args[1] = {&rect_type};
  CHECK(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_double, rect_args) == FFI_OK, "prep area");
  Rect r = {1, 2, 3, 4};
  void *area_values[1] = {&r};
  double result = 0;
  ffi_call(&cif, FFI_FN(area), &result, area_values);
  CHECK(result == 12.0, "call area");

  ffi_type *lanes[5] = {&ffi_type_float, &ffi_type_float, &ffi_type_float, &ffi_type_float,
                        NULL};
  ffi_type vec_type;
  memset(&vec_type, 0, sizeof vec_type);
  vec_type.type = FFI_TYPE_VECTOR;
  vec_type.elements = lanes;
  ffi_type *vec_args[2] = {&vec_type, &ffi_type_float};
  CHECK(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &vec_type, vec_args) == FFI_OK, "prep scale");
  float4 v = {1, 2, 3, 4};
  float s = 2;
  void *scale_values[2] = {&v, &s};
  float4 scaled = {0, 0, 0, 0};
  ffi_call(&cif, FFI_FN(scale), &scaled, scale_values);
  CHECK(scaled.x == 2 && scaled.y == 4 && scaled.z == 6 && scaled.w == 8, "call scale");

  ffi_type *closure_args[1] = {&ffi_type_sint};
  CHECK(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_sint, closure_args) == FFI_OK, "prep closure");
  void *code = NULL;
  ffi_closure *closure = ffi_closure_alloc(sizeof(ffi_closure), &code);
  CHECK(closure != NULL, "closure alloc");
  if (closure) {
    int offset = 1;
    CHECK(ffi_prep_closure_loc(closure, &cif, double_it, &offset, code) == FFI_OK, "prep closure loc");
    CHECK(((int (*)(int))code)(20) == 41, "call closure");
    ffi_closure_free(closure);
  }

  if (failures) return 1;
  printf("libffi %s smoke test passed\n", ffi_get_version());
  return 0;
}
