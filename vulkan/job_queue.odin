package game_vulkan

import "core:container/queue"
import "core:sync"
import vk "vendor:vulkan"

Resource_Usage :: enum {
    READ_ONLY,
    READ_WRITE,
    WRITE
}

Raw_Resource :: union {
    Raw_Buffer_Slice,
    vk.Image
}

Job_Handle :: distinct u32

Job_Resource :: struct {
    usage: Resource_Usage,
    asset: Raw_Resource
}

Jobby :: struct {
    id : Job_Handle,
    dependencies : [dynamic]Job_Handle,
    resources : []Job_Resource
}

Jobby_Queue :: struct {
    q : queue.Queue(Jobby),
    mutex : sync.Mutex
}

push :: proc(q: ^Jobby_Queue, resources: ..Job_Resource) -> Job_Handle {
    sync.lock(&q.mutex)
    defer sync.unlock(&q.mutex)

    handle := Job_Handle(q.q.len)

    queue.push_back(&q.q, Jobby{
        id=handle,
        dependencies={},
        resources=resources}
    )

    return handle
}

pop :: proc(q: ^Jobby_Queue) -> Jobby {
    sync.lock(&q.mutex)
    defer sync.unlock(&q.mutex)

    job := queue.pop_front(&q.q)

    return job
}

add_dependency :: proc(q: ^Jobby_Queue, jobby, dependant: Job_Handle) {
    sync.lock(&q.mutex)
    defer sync.unlock(&q.mutex)

    for i in q.q.offset..<q.q.len {
        if q.q.data[i].id == jobby {
            append(&q.q.data[i].dependencies, dependant)
        }
    }
}

// need to manually process dependencies - compute necessary dependencies based on resources required,
// compute ordering that jobs need to go in - return array of "Final Jobs" - job data that includes semaphore value



/** =============== OLD STUFF ================ **/
Graphics_Job :: struct {
    pipeline            : Pipeline,
    data                : []Buffer,
}

Compute_Job :: struct {
    // fill in later
}

Transfer_Job :: struct {
    src_buffer          : Raw_Buffer_Slice,
    dest_buffer         : Raw_Buffer_Slice,
    descriptor          : Maybe(vk.DescriptorSet)
}

Job_Data :: union {
    Graphics_Job,
    Compute_Job,
    Transfer_Job
}

Dependency :: union {
    vk.Buffer,
    vk.Pipeline
}

Job :: struct {
    // the main data that will get handled and sent off
    // to the GPU for processing
    data                : Job_Data,

    // this uses a map to represent a set of pointers, rather than a list
    // once jobs are processing, this set should be not be considered valid
    // all values in this map are 'nil'
    depends_on          : map[Dependency]rawptr,

    // this is equivalent to the index of the job in the queue - this is used as
    // the signal semaphore for the job
    timeline_stage      : u32,
}

Job_Queue :: struct {
    jobs            : queue.Queue(Job),
    mutex           : sync.Mutex,
    timeline_sems   : []vk.Semaphore,
    dependencies     : map[Dependency]u32,
}

push :: proc(q : ^Job_Queue, job: Job_Data) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)

    full_job : Job
    full_job.data = job
    full_job.timeline_stage = u32(queue.len(q.jobs))

    switch subjob in full_job.data {
        case Graphics_Job:
            q.dependencies[subjob.pipeline.data] = full_job.timeline_stage
            for &buf in subjob.data {
                add_job_dependency(&full_job, buf.buf)
            }
        case Compute_Job:
        case Transfer_Job:
            q.dependencies[subjob.dest_buffer.buffer] = full_job.timeline_stage
            add_job_dependency(&full_job, subjob.src_buffer.buffer)
    }

    queue.push_back(&q.jobs, full_job)
}

pop :: proc(q : ^Job_Queue) -> (job : Job, ok : bool) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)

    job, ok = queue.pop_front_safe(&q.jobs)

    return
}

q_len :: proc(q : ^Job_Queue) -> int {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)

    return queue.len(q.jobs)
}

add_job_dependency :: proc(job : ^Job, dependency : Dependency) {
    job.depends_on[dependency] = nil
}
