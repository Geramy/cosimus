/*
 * The file tweaked from its original looks by Andrew Yourtchenko 2009
 */

/*
 * Copyright (c) 2008, 3Di Inc (www.3di.jp)
 * All rights reserved
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 * Neither the name of 3Di  nor the
 * names of its contributors may be used to endorse or promote products
 * derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE DEVELOPERS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>

#include "template.h"

const int endian_test = 1;
#define is_bigendian() ( (*(char*) &endian_test) == 0 )

struct uuid {
    u32t time_low;
    u16t time_mid;
    u16t time_hi_and_version;
    u16t clock_seq;
    u8t node[6];
};

void UUIDToString(char *val, const struct uuid *uu);
void UUIDFromString(const char* data_ptr, struct uuid *uu);
char *UUIDFromBytes(int a, short b, short c, u8t *p);
char *UUIDFromU64(u64t value);

#define APPENDED_ACKS 0x10
#define RESENT 0x20
#define RELIABLE 0x40
#define ZEROCODED 0x80
#define Low 1
#define Medium 2
#define High 3


void GetAcks(int* count, u32t* acks, int maxAcks, u8t* udpMessage, int udpMessageLength)
{
    int i;
    if(HasAcks(udpMessage))
    {
        *count = udpMessage[udpMessageLength--];

        for (i = 0; i < *count && i<maxAcks; i++)
        {
            acks[i] = (u32t)(
                    (udpMessage[(udpMessageLength - i * 4) - 3] << 24) |
                    (udpMessage[(udpMessageLength - i * 4) - 2] << 16) |
                    (udpMessage[(udpMessageLength - i * 4) - 1] <<  8) |
                    (udpMessage[(udpMessageLength - i * 4)    ]));
        }
    }
    else
    {
        *count=0;
    }
}

int AppendAcks(u32t* acks, int numAcks, u8t* udpMessage, int udpMessageLength)
{
    // Returns the new length
    u32t ack;
    int i=udpMessageLength, j;

    for(j=0; j<numAcks; j++)
    {
        ack=acks[j];
        udpMessage[i++] = (u8t)((ack >> 24) % 256);
        udpMessage[i++] = (u8t)((ack >> 16) % 256);
        udpMessage[i++] = (u8t)((ack >> 8) % 256);
        udpMessage[i++] = (u8t)(ack % 256);
    }
    if (numAcks > 0) 
    { 
        SetHasAcks(udpMessage, 1);
        udpMessage[i++] = (u8t) numAcks;
    }
    return i;
}

int IsZeroCoded(u8t* data)
{
    return (data[0] & ZEROCODED) != 0;
}

void SetZeroCoded(u8t* data, int val)
{
    if (val) {
        data[0] |= (u8t) ZEROCODED;
    } else {
        u8t mask = (u8t) ZEROCODED ^ 0xFF;
        data[0] &= mask;
    }
}

int IsReliable(u8t* data)
{
    return (data[0] & RELIABLE)!=0; 
}
void SetReliable(u8t* data, int val)
{
    if(val)
    {
        data[0] |= (u8t) RELIABLE;
    } 
    else
    {
        u8t mask = (u8t) RELIABLE ^ 0xFF;
        data[0] &= mask;
    }
}

int HasAcks(u8t* data)
{
    return (data[0] & APPENDED_ACKS)!=0; 
}
void SetHasAcks(u8t* data, int val)
{
    if(val)
    {
        data[0] |= (u8t) APPENDED_ACKS;
    } 
    else
    {
        u8t mask = (u8t) APPENDED_ACKS ^ 0xFF;
        data[0] &= mask;
    }
}

u32t GetSequenceNumber(u8t* data)
{
    return (u32t) ((data[1] << 24) + (data[2] << 16) +
            (data[3] << 8) + data[4]);
}

void SetSequenceNumber(u8t* data, u32t seqNumber)
{
    data[1] = (u8t) (seqNumber >> 24);
    data[2] = (u8t) (seqNumber >> 16);
    data[3] = (u8t) (seqNumber >> 8);
    data[4] = (u8t) (seqNumber % 256);
}

u16t GetPacketFrequency(u8t* data)
{
    u8t d6=(u8t) data[6];
    u8t d7=(u8t) data[7];
    if(d6==0xff && d7==0xff) return Low;
    if(d6==0xff) return Medium;
    return High;
}

u16t GetPacketID(u8t* data)
{
    switch (GetPacketFrequency(data)) {
        case Low:
            return (u16t) ((data[8] << 8) + data[9]);
        case Medium:
            return (u16t) data[7];
    }
    return (u16t) data[6];
}

void SetPacketID(u8t* data, int frequency, u16t val)
{
    switch (frequency) {
        case Low:
            data[6] = 0xff;
            data[7] = 0xff;
            data[8] = (u8t) (val >> 8);
            data[9] = (u8t) (val % 256);
            break;
        case Medium:
            data[6] = 0xff;
            data[7] = (u8t) val;
            break;
        case High:
            data[6] = (u8t) val;
            break;
    }
}

void Header_UDP(u8t* data, u16t packetId, int frequency, u8t flags)
{
    memset(data, '\0', 10);
    data[0] = flags;
    SetPacketID(data, frequency, packetId);
}
void UUIDToString(char *val, const struct uuid *uu)
{
    if(val==NULL) return;
    sprintf(val, "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            uu->time_low, uu->time_mid, uu->time_hi_and_version,
            uu->clock_seq >> 8, uu->clock_seq & 0xFF,
            uu->node[0], uu->node[1], uu->node[2],
            uu->node[3], uu->node[4], uu->node[5]);
}

void UUIDFromString(const char* data_ptr, struct uuid *uu)
{
    int i;
	char buf[3];
    const char *cp;

	uu->time_low = strtoul(data_ptr, NULL, 16);
	uu->time_mid = (u16t) strtoul(data_ptr+9, NULL, 16);
	uu->time_hi_and_version = (u16t) strtoul(data_ptr+14, NULL, 16);
	uu->clock_seq = (u16t) strtoul(data_ptr+19, NULL, 16);
	cp = data_ptr+24;
	buf[2] = 0;
	for (i=0; i < 6; i++) {
		buf[0] = *cp++;
		buf[1] = *cp++;
		uu->node[i] = (u8t) strtoul(buf, NULL, 16);
	}
}

char *UUIDFromBytes(int a, short b, short c, u8t *p)
{
    int i;
    char *output;
    struct uuid uu;
    uu.time_low=a;
    uu.time_mid=b;
    uu.time_hi_and_version=c;
    uu.clock_seq=256*p[0]+p[1];
    for(i=0; i<6; i++) uu.node[i]=p[2+i];
/*    for(i=2; i<6; i++) uu.node[i]=0;*/
    output=(char *) malloc(40);
    UUIDToString(output, &uu);
    return output;
}

char *UUIDFromU64(u64t value)
{
    return UUIDFromBytes(0,0,0,(u8t *) &value);
}

void LLUUID_UDP(const char* uuid_string, u8t* data, int *i)
{
    int tmp;
    struct uuid uu;

    UUIDFromString(uuid_string, &uu);

    tmp = uu.time_low; 
    data[*i+3] = (u8t) tmp;
    tmp >>= 8; data[*i+2] = (u8t) tmp;
    tmp >>= 8; data[*i+1] = (u8t) tmp;
    tmp >>= 8; data[*i+0] = (u8t) tmp;

    tmp = uu.time_mid;
    data[*i+5] = (u8t) tmp;
    tmp >>= 8; data[*i+4] = (u8t) tmp;

    tmp = uu.time_hi_and_version;
    data[*i+7] = (u8t) tmp;
    tmp >>= 8; data[*i+6] = (u8t) tmp;

    tmp = uu.clock_seq;
    data[*i+9] = (u8t) tmp;
    tmp >>= 8; data[*i+8] = (u8t) tmp;

    memcpy(&data[*i+10], uu.node, 6);

    *i+=16;
}

void UDP_LLUUID(char* uuid_string, u8t* data, int *i)
{
    struct uuid uu;
    int tmp = data[*i];
    tmp = (tmp << 8) | data[*i+1];
    tmp = (tmp << 8) | data[*i+2];
    tmp = (tmp << 8) | data[*i+3];
    uu.time_low = tmp;
    tmp = data[*i+4];
    tmp = (tmp << 8) | data[*i+5];
    uu.time_mid = tmp;
    tmp = data[*i+6];
    tmp = (tmp << 8) | data[*i+7];
    uu.time_hi_and_version = tmp;
    tmp = data[*i+8];
    tmp = (tmp << 8) | data[*i+9];
    uu.clock_seq = tmp;
    memcpy(&uu.node, &data[*i+10], 6);

    UUIDToString(uuid_string, &uu);
    *i+=16;
}

/* Variable values are always passed as a pair (ptr, length). */
void Variable2_UDP(const char *val, int length, u8t* data, int *i)
{
    if (length >= 0 && length <= 65535) {
      data[*i + 0] = (u8t) (length % 256);
      data[*i + 1] = (u8t) (length / 256);
      *i+=2;
      memcpy(&data[*i], val, length);
      *i+=length;
    } else {
      assert("Length of Variable2 is illegal");
    }
}

/* return the length, and make the value also a C string, just in case */
int UDP_Variable2(char *val, u8t* data, int *i)
{
    int length = (int) (data[*i + 0] + data[*i + 1] * 256);
    if(val != NULL) {
      *i+=2;
      memcpy(val, &data[*i], length);
      *i+=length;
      val[length]='\0'; /* make this a C string */
    }
    return length;
}
/* Variable values are passed always as (ptr, length) pair */
void Variable1_UDP(const char *val, int length, u8t* data, int *i)
{
    if (length >= 0 && length <= 255) {
      data[*i] = (u8t) length;
      *i+=1;
      memcpy(&data[*i], val, length);
      *i+=length;
    } else {
      assert("Length of the Variable1 is illegal");
    }
}
/* return length of data only, not advancing in case val is NULL */
int UDP_Variable1(char *val, u8t* data, int *i)
{
    int length = (int) data[*i];
    if (val != NULL) {
      *i+=1;
      memcpy(val, &data[*i], length);
      *i+=length;
      val[length]='\0'; /* make this a C string */
    }
    return length;
}

void LLQuaternion_UDP(f32t x, f32t y, f32t z, f32t w, u8t* data, int *i)
{
    f32t fx, fy, fz;
    f32t norm = (f32t) sqrt(x * x + y * y + z * z + w * w);
    if (norm == 0) { 
      printf("Error: Quaternion normalized to zero"); 
      norm = 1;
    }
    norm = 1 / norm;

    if (w >= 0) {
        fx = x;
        fy = y;
        fz = z;
    } else {
        fx = -x;
        fy = -y;
        fz = -z;
    }

    F32_UDP(norm * fx, data, i);
    F32_UDP(norm * fy, data, i);
    F32_UDP(norm * fz, data, i);
}

void UDP_LLQuaternion(f32t* x, f32t* y, f32t* z, f32t* w, u8t* data, int *i)
{
    f32t xyzsum;

    UDP_F32(x, data, i);
    UDP_F32(y, data, i);
    UDP_F32(z, data, i);

    xyzsum = 1 - (*x)*(*x)- (*y)*(*y)- (*z)*(*z);
    if(w!=NULL) *w = (xyzsum > 0) ? (f32t) sqrt(xyzsum) : 0;
}

void LLVector3_UDP(f32t x, f32t y, f32t z, u8t* data, int *i)
{
    F32_UDP(x, data, i);
    F32_UDP(y, data, i);
    F32_UDP(z, data, i);
}

void UDP_LLVector3(f32t* x, f32t* y, f32t* z, u8t* data, int *i)
{
    UDP_F32(x, data, i);
    UDP_F32(y, data, i);
    UDP_F32(z, data, i);
}

void LLVector4_UDP(f32t x, f32t y, f32t z, f32t s, u8t* data, int *i)
{
    F32_UDP(x, data, i);
    F32_UDP(y, data, i);
    F32_UDP(z, data, i);
    F32_UDP(s, data, i);
}

void UDP_LLVector4(f32t* x, f32t* y, f32t* z, f32t* s, u8t* data, int *i)
{
    UDP_F32(x, data, i);
    UDP_F32(y, data, i);
    UDP_F32(z, data, i);
    UDP_F32(s, data, i);
}

void LLVector3d_UDP(f64t x, f64t y, f64t z, u8t* data, int *i)
{
    F64_UDP(x, data, i);
    F64_UDP(y, data, i);
    F64_UDP(z, data, i);
}

void UDP_LLVector3d(f64t* x, f64t* y, f64t* z, u8t* data, int *i)
{
    UDP_F64(x, data, i);
    UDP_F64(y, data, i);
    UDP_F64(z, data, i);
}

void Bool_UDP(int val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) ((val) ? 1 : 0);
    *i+=1;
}

void UDP_Bool(int* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (data[*i] != 0) ? (int) 1 : (int) 0;
    *i+=1;
}

void Fixed_UDP(const u8t *val, int size, u8t* data, int *i)
{
    memcpy(&data[*i], val, size);
    *i+=size;
}

void UDP_Fixed(u8t *val, int size, u8t* data, int *i)
{
    if(val!=NULL) memcpy(val, &data[*i], size);
    *i+=size;
}

void S16_UDP(short val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) (val % 256);
    data[*i + 1] = (u8t) ((val >> 8) % 256);
    *i+=2;
}

void UDP_S16(short* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (short) (data[*i + 0] + (data[*i + 1] << 8));
    *i+=2;
}

void U64_UDP(u64t val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) (val % 256);
    data[*i + 1] = (u8t) ((val >> 8) % 256);
    data[*i + 2] = (u8t) ((val >> 16) % 256);
    data[*i + 3] = (u8t) ((val >> 24) % 256);
    data[*i + 4] = (u8t) ((val >> 32) % 256);
    data[*i + 5] = (u8t) ((val >> 40) % 256);
    data[*i + 6] = (u8t) ((val >> 48) % 256);
    data[*i + 7] = (u8t) ((val >> 56) % 256);
    *i+=8;
}

void UDP_U64(u64t* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (u64t)
        ((u64t) data[*i + 0] + ((u64t) data[*i + 1] << 8) +
         ((u64t) data[*i + 2] << 16) + ((u64t) data[*i + 3] << 24) +
         ((u64t) data[*i + 4] << 32) + ((u64t) data[*i + 5] << 40) +
         ((u64t) data[*i + 6] << 48) + ((u64t) data[*i + 7] << 56));
    *i+=8;
}

void F32_UDP(f32t val, u8t* data, int *i)
{
    u8t *v=(u8t *) &val;

    if (is_bigendian()) {
        data[*i + 3]=v[0];
        data[*i + 2]=v[1];
        data[*i + 1]=v[2];
        data[*i + 0]=v[3];
    } else {
        data[*i + 0]=v[0];
        data[*i + 1]=v[1];
        data[*i + 2]=v[2];
        data[*i + 3]=v[3];
    }

    *i+=4;
}

void UDP_F32(f32t* val, u8t* data, int *i)
{
    u8t *v=(u8t *) val;

    if(val!=NULL) {
        if (is_bigendian()) {
            v[0]=data[*i + 3];
            v[1]=data[*i + 2];
            v[2]=data[*i + 1];
            v[3]=data[*i + 0];
        } else {
            v[0]=data[*i + 0];
            v[1]=data[*i + 1];
            v[2]=data[*i + 2];
            v[3]=data[*i + 3];
        }
    }

    *i+=4;
}

void F64_UDP(f64t val, u8t* data, int *i)
{
    u8t *v=(u8t *) &val;

    if (is_bigendian()) {
        data[*i + 7]=v[0];
        data[*i + 6]=v[1];
        data[*i + 5]=v[2];
        data[*i + 4]=v[3];
        data[*i + 3]=v[4];
        data[*i + 2]=v[5];
        data[*i + 1]=v[6];
        data[*i + 0]=v[7];
    } else {
        data[*i + 0]=v[0];
        data[*i + 1]=v[1];
        data[*i + 2]=v[2];
        data[*i + 3]=v[3];
        data[*i + 4]=v[4];
        data[*i + 5]=v[5];
        data[*i + 6]=v[6];
        data[*i + 7]=v[7];
    }

    *i+=8;
}

void UDP_F64(f64t* val, u8t* data, int *i)
{
    u8t *v=(u8t *) val;

    if(val!=NULL) {
        if (is_bigendian()) {
            v[0]=data[*i + 7];
            v[1]=data[*i + 6];
            v[2]=data[*i + 5];
            v[3]=data[*i + 4];
            v[4]=data[*i + 3];
            v[5]=data[*i + 2];
            v[6]=data[*i + 1];
            v[7]=data[*i + 0];
        } else {
            v[0]=data[*i + 0];
            v[1]=data[*i + 1];
            v[2]=data[*i + 2];
            v[3]=data[*i + 3];
            v[4]=data[*i + 4];
            v[5]=data[*i + 5];
            v[6]=data[*i + 6];
            v[7]=data[*i + 7];
        }
    }

    *i+=8;
}

void U32_UDP(u32t val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) (val % 256);
    data[*i + 1] = (u8t) ((val >> 8) % 256);
    data[*i + 2] = (u8t) ((val >> 16) % 256);
    data[*i + 3] = (u8t) ((val >> 24) % 256);
    *i+=4;
}

void UDP_U32(u32t *val, u8t* data, int *i)
{
    if(val!=NULL) *val = (u32t)
        (data[*i + 0] + (data[*i + 1] << 8) + 
         (data[*i + 2] << 16) + (data[*i + 3] << 24));
    *i+=4;
}

void S32_UDP(s32t val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) (val % 256);
    data[*i + 1] = (u8t) ((val >> 8) % 256);
    data[*i + 2] = (u8t) ((val >> 16) % 256);
    data[*i + 3] = (u8t) ((val >> 24) % 256);
    *i+=4;
}

void UDP_S32(s32t* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (s32t)
        (data[*i + 0] + (data[*i + 1] << 8) +
         (data[*i + 2] << 16) + (data[*i + 3] << 24));
    *i+=4;
}

void U16_UDP(u16t val, u8t* data, int *i)
{
    data[*i + 0] = (u8t) (val % 256);
    data[*i + 1] = (u8t) ((val >> 8) % 256);
    *i+=2;
}

void UDP_U16(u16t* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (u16t) (data[*i + 0] + (data[*i + 1] << 8));
    *i+=2;
}

void IPPORT_UDP(u16t val, u8t* data, int* i) {
    data[*i + 0] = (u8t)((val >> 8) % 256);
    data[*i + 1] = (u8t)(val % 256);
    *i+=2;
}

void UDP_IPPORT(u16t* val, u8t* data, int* i) {
    if(val!=NULL) *val = (u16t)((data[*i + 0] << 8) + data[*i + 1]);
    *i+=2;
}

void U8_UDP(u8t val, u8t* data, int *i)
{
    data[*i] = val;
    *i+=1;
}

void UDP_U8(u8t* val, u8t* data, int *i)
{
    if(val!=NULL) *val = data[*i];
    *i+=1;
}

void S8_UDP(s8t val, u8t* data, int *i)
{
    data[*i] = (u8t) val;
    *i+=1;
}

void UDP_S8(s8t* val, u8t* data, int *i)
{
    if(val!=NULL) *val = (s8t) data[*i];
    *i+=1;
}


