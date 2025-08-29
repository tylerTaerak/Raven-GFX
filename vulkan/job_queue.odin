package game_vulkan

import "core:container/queue"
import "core:sync"
import vk "vendor:vulkan"


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
