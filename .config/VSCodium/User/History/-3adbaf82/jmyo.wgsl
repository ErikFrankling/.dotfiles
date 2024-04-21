const SAMPLES_PER_PIXEL: u32 = 25u;
const MAX_DEPTH: u32 = 50u;
const GLOBAL_ILUMINATION_COLOR: vec3f = vec3f(0.01, 0.01, 0.01);//vec3f(0.1, 0.1, 0.1);
const VIEWPORT_DISTANCE: f32 = 1.0;
const CAMERA_POSITION: vec3f = vec3f(0.0, 0.0, 0.0);
const WIDTH: u32 = HEIGHT;
const HEIGHT: u32 = 512u;
const SKY_COLOR: vec3f = vec3f(0.3, 0.5, 0.7);
//const SKY_COLOR: vec3f = vec3f(0.0, 0.0, 0.0);
const SECOUNDS_PER_REVOLUTION: f32 = 5.0;
const FPS: f32 = 5.0;

struct Sphere {
    center: vec3<f32>,
    radius: f32,
    id: u32,
    material: Material,
}

struct Material {
    color: vec3<f32>,
    is_light: bool,
}

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}

struct Image {
    pixels: array<vec3f>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;

    let pos = vec2f(f32((in_vertex_index << 1u) & 2u), f32(in_vertex_index & 2u));
    out.clip_position = vec4f(pos * 2.0 - 1.0, 0.0, 1.0);

    return out;
}

const OBJECT_COUNT: u32 = 4u;

@fragment
fn fs_main(fragData: VertexOutput) -> @location(0) vec4<f32>
{
    let viewport = vec2f(fragData.clip_position.x - f32(WIDTH / 2u), fragData.clip_position.y - f32(HEIGHT / 2u));

    return main(viewport);
    // return vec4<f32>(1.0, 0.5, 0.3, 1.0);
}

ComputeOut {
    camera_position: vec3<f32>,
    spheres: array<Sphere, OBJECT_COUNT>,
}

@group(0)
@binding(0)
var<storage, read_write> iter: u32 = 0u;
// var<storage, read_write> compute_out: ComputeOut;
// var tex: texture_storage_2d<rgba8unorm, write>;

@compute
@workgroup_size(1)
fn cs_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let viewport = vec2f(f32(id.x) - f32(WIDTH / 2u), f32(id.y) - f32(HEIGHT / 2u));

    // textureStore(tex, id.xy, main(viewport));
    // textureStore(tex, id.xy, vec4<f32>(1.0, 0.5, 0.3, 1.0));
}

fn main(viewport: vec2<f32>) -> vec4f {
    if (viewport.x == 1.0 && viewport.y == 1.0) {
        iter += 1u;
    }
    rng_state = u32(viewport.y * f32(WIDTH) + viewport.x) + 10000000u;

    var spheres: array<Sphere, OBJECT_COUNT> = array<Sphere, OBJECT_COUNT>(
        Sphere(
            vec3<f32>(0.0, 0.0, 4.0),
            0.7,
            0u,
            Material(
                vec3<f32>(0.3, 0.7, 0.5),
                false
            ),
        ),
        Sphere(
            vec3<f32>(0.5, -2.0, 4.0),
            0.7,
            1u,
            Material(
                vec3<f32>(1.0, 1.0, 1.0),
                true
            )
        ),
        Sphere(
            vec3<f32>(1.7, 0.0, 4.0),
            0.7,
            2u,
            Material(
                vec3<f32>(1.0, 1.0, 1.0),
                true
            )
        ),
        Sphere(
            vec3<f32>(0.0, 100.75, 4.0),
            100.0,
            3u,
            Material(
                vec3<f32>(0.5, 1.0, 0.3),
                false
            )
        )
    );

    var acc = vec3<f32>(0.0, 0.0, 0.0);

    let pi: f32 = radians(180.0);

    let angle = f32(iter) * ((2.0 * pi) / (FPS * SECOUNDS_PER_REVOLUTION));
    let camera_position = CAMERA_POSITION * 
        rotaton_matrix(vec3<bool>(true, false, false), angle );

    for (var i = 0u; i < SAMPLES_PER_PIXEL; i++) {
        for (var i = 0u; i < SAMPLES_PER_PIXEL; i++) {
            let ray = Ray(
                CAMERA_POSITION,
                vec3f(
                    (viewport.x + rand_pcg()) / f32(WIDTH),
                    (viewport.y + rand_pcg()) / f32(HEIGHT),
                    VIEWPORT_DISTANCE,
                )
            );
            
            acc += ray_caste(ray, spheres);
        }
    }

    return vec4f((acc / f32(SAMPLES_PER_PIXEL)), 1.0);
}

fn ray_caste(ray : Ray, spheres: array<Sphere, OBJECT_COUNT>) -> vec3f {
    var spheres_var: array<Sphere, OBJECT_COUNT> = spheres;

    var current_color: vec3f = vec3f(1.0, 1.0, 1.0);
    var current_ray = ray;

    for (var depth = 0u; depth < MAX_DEPTH; depth++) {
        var has_hit: bool = false;
        var hit_record: HitRecord;
        var closest_so_far: f32 = 0.0;
        let t_min: f32 = 0.01;

        for (var i: u32 = 0u; i < OBJECT_COUNT; i++) {
            let object: Sphere = spheres_var[i];

            let oc = current_ray.origin - object.center;
            let a = dot(current_ray.direction, current_ray.direction);
            let b = 2.0 * dot(oc, current_ray.direction);
            let c = dot(oc, oc) - object.radius * object.radius;
            let discriminant = b * b - 4.0 * a * c;

            if discriminant > 0.0 {
                var t = (-b - sqrt(discriminant)) / 2.0 * a;

                if (!has_hit || t < closest_so_far) && t > t_min {
                    let poi32 = ray_at(current_ray, t);
                    let normal = (poi32 - object.center) / object.radius;

                    hit_record = HitRecord(poi32, normal, t, object.id);
                    closest_so_far = t;
                    has_hit = true;
                    break;
                }
            }
        }

        if has_hit {
            // current_color = vec3f(1.0, 1.0, 1.0);
            let material = spheres_var[hit_record.object_id].material;
            current_color *= material.color;

            if material.is_light {
                return current_color;
            } else {
                current_ray = diffuse_scatter(current_ray, hit_record, material);
            }
        }
        else {
            // current_color = vec3f(1.0, 0.0, 0.0);
            if depth == 0u {
                return SKY_COLOR;
            }
            else {
                return current_color * GLOBAL_ILUMINATION_COLOR;
            }
        }
    }

    return vec3f(0.0, 0.0, 0.0);
}

struct HitRecord {
    poi32: vec3f,
    normal: vec3f,
    t: f32,
    object_id: u32,
}

fn diffuse_scatter(ray: Ray, hit_record: HitRecord, material: Material) -> Ray {
    return Ray(
        hit_record.poi32,
        hit_record.normal + random_unit_vector(),
    );
}

fn rotaton_matrix(axis: vec3<bool>, angle: f32) -> mat3x3f {
    let c = cos(angle);
    let s = sin(angle);
    let t = 1.0 - c;

    let x = f32(axis.x) * mat3x3f (
        vec3f(1.0, 0.0, 0.0),
        vec3f(0.0, c, -s),
        vec3f(0.0, s, c)
    );

    let y = f32(axis.y) * mat3x3f (
        vec3f(c, 0.0, s),
        vec3f(0.0, 1.0, 0.0),
        vec3f(-s, 0.0, c)
    );

    let z = f32(axis.z) * mat3x3f (
        vec3f(c, -s, 0.0),
        vec3f(s, c, 0.0),
        vec3f(0.0, 0.0, 1.0)
    );

    return x * y * z;
}
fn random_unit_vector() -> vec3f {
    return normalize(vec3f(
        rand_pcg() * 2.0 - 1.0,
        rand_pcg() * 2.0 - 1.0,
        rand_pcg() * 2.0 - 1.0,
    ));
}

fn ray_at(ray: Ray, t: f32) -> vec3f {
    return ray.origin + ray.direction * t;
}

var<private> rng_state: u32;

fn rand_pcg() -> f32 {
    let state: u32 = rng_state;
    rng_state = rng_state * 747796405u + 2891336453u;
    let word: u32 = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return f32((word >> 22u) ^ word) / 4294967295.0;
}
