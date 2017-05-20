//
//  main.m
//  performance-test-macOS
//
//  Created by NiYao on 05/05/2017.
//  Copyright © 2017 suneny. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <mach/task.h>
#import <mach/task_info.h>
#include <mach/mach.h>
#include <mach-o/ldsyms.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

float app_cpu_usage() {
    kern_return_t kern_return;
    task_info_data_t info;
    mach_msg_type_number_t infoCount = TASK_INFO_MAX;
    kern_return = task_info(mach_task_self(), TASK_BASIC_INFO,(task_info_t)info, &infoCount);
    if(kern_return != KERN_SUCCESS) {
        return -1;
    }
    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;
    thread_info_data_t thinfo;
    mach_msg_type_number_t thread_info_count;
    thread_basic_info_t basic_info_th;
    kern_return = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kern_return != KERN_SUCCESS) {
        return -1;
    }
    float total_cpu = 0;
    int j;
    for (j = 0; j < thread_count; j++) {
        thread_info_count = THREAD_INFO_MAX;
        kern_return = thread_info(thread_list[j], THREAD_BASIC_INFO, (thread_info_t)thinfo,&thread_info_count);
        if (kern_return != KERN_SUCCESS) {
            return -1;
        }
        basic_info_th = (thread_basic_info_t)thinfo;
        if (!(basic_info_th -> flags & TH_FLAGS_IDLE)) {
            total_cpu += basic_info_th -> cpu_usage / (float)TH_USAGE_SCALE * 100.0;
        }
    }
    vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    return total_cpu;
}

dispatch_queue_t monitor_queue() {
    static dispatch_queue_t monitor_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        monitor_queue = dispatch_queue_create("ny.monitor.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    return monitor_queue;
}

unsigned long get_used_memory() {
    task_basic_info_data_t info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    if (kerr == KERN_SUCCESS) {
        return info.resident_size;
    } else {
        return 0;
    }
}

unsigned long get_free_memory() {
    mach_port_t host = mach_host_self();
    mach_msg_type_number_t size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    vm_statistics_data_t vmstat;
    host_page_size(host, &pagesize);
    host_statistics(host, HOST_VM_INFO, (host_info_t)&vmstat, &size);
    return vmstat.free_count * pagesize;
}

static int count = 0;
static BOOL fireTimer = 1;

void gcd_timer() {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, monitor_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        printf("CPU Usage[%d]: %f％\n"
               "Used Memory/Free Memory : %lu/%lu\n"
               , count++, app_cpu_usage(), get_used_memory(), get_free_memory()); // print before plus
        if (!fireTimer) {
            dispatch_source_cancel(timer);
        }
    });
    dispatch_resume(timer);
    [[NSRunLoop currentRunLoop] run];
}

kern_return_t lsPorts(task_t TargetTask) {
    kern_return_t kr;
    mach_port_name_array_t portNames = NULL;
    mach_msg_type_number_t portNamesCount;
    mach_port_type_array_t portRightTypes = NULL;
    mach_msg_type_number_t portRightTypesCount;
    
    unsigned int p;
    
    kr = mach_port_names(TargetTask, &portNames, &portNamesCount, &portRightTypes, &portRightTypesCount);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Error getting mach_port_names.. %d\n", kr);
        return (kr);
    }
    
    for (p = 0; p < portNamesCount; p++) {
        printf("Port Name: 0x%x \t Port Right Type: 0x%x\n", portNames[p], portRightTypes[p]);
    }
    return kr;
    
}

void lsPortsEntries(const char * argv[]) {
    task_t targetTask;
    kern_return_t kr;
    int pid = atoi(argv[0]);
    kr = task_for_pid(mach_task_self(), pid, &targetTask);
    lsPorts(targetTask);
    kr = mach_port_deallocate(mach_task_self(), targetTask);
}

void host_info_tool() {
    mach_port_t host = mach_host_self();
    kern_return_t rc;
    char buf[1024];
    host_basic_info_t hi;
    unsigned int len = 1024;
    rc = host_info(host, HOST_BASIC_INFO, (host_info_t)buf, &len);
    if (rc != 0) {
        fprintf(stderr, "Nope\n");
        return ;
    }
    
    hi = (host_basic_info_t)buf;
    printf("Availabel CPU: %d \t Max Memory: %llu \n", hi->avail_cpus, hi->max_mem);
    printf("Physical CPU: %d \t Max Physical CPU: %d \n", hi->physical_cpu, hi->physical_cpu_max);
    printf("Logical CPU: %d \t Max Logical CPU: %d \n", hi->logical_cpu, hi->logical_cpu_max);
    printf("CPU Type: %d \t Thread Type: %d \n", hi->cpu_subtype, hi->cpu_threadtype);
    printf("Memory Size: %d \t Max Memory Size: %llu \n", hi->memory_size, hi->max_mem);
}

#define NUM_THREADS	8

char *messages[NUM_THREADS];

struct thread_data
{
    int	thread_id;
    int  sum;
    char *message;
};

struct thread_data thread_data_array[NUM_THREADS];

void *PrintHello(void *threadarg)
{
    int taskid, sum;
    char *hello_msg;
    struct thread_data *my_data;
    
    sleep(1);
    my_data = (struct thread_data *) threadarg;
    taskid = my_data->thread_id;
    sum = my_data->sum;
    hello_msg = my_data->message;
    printf("Thread %d: %s  Sum=%d\n", taskid, hello_msg, sum);
    pthread_exit(NULL);
}
void ptread_test() {
    pthread_t threads[NUM_THREADS];
    int *taskids[NUM_THREADS];
    int rc, t, sum;
    
    sum=0;
    messages[0] = "English: Hello World!";
    messages[1] = "French: Bonjour, le monde!";
    messages[2] = "Spanish: Hola al mundo";
    messages[3] = "Klingon: Nuq neH!";
    messages[4] = "German: Guten Tag, Welt!";
    messages[5] = "Russian: Zdravstvytye, mir!";
    messages[6] = "Japan: Sekai e konnichiwa!";
    messages[7] = "Latin: Orbis, te saluto!";
    
    for(t=0;t<NUM_THREADS;t++) {
        sum = sum + t;
        thread_data_array[t].thread_id = t;
        thread_data_array[t].sum = sum;
        thread_data_array[t].message = messages[t];
        printf("Creating thread %d\n", t);
        rc = pthread_create(&threads[t], NULL, PrintHello, (void *)
                            &thread_data_array[t]);
        if (rc) {
            printf("ERROR; return code from pthread_create() is %d\n", rc);
            exit(-1);
        }
    }
    pthread_exit(NULL);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        gcd_timer();
    }
    return 0;
}
